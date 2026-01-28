local task_state = require("runtime.task_state")

local M = {}

function M.new(resource_provider, machine_allocator)
  local self = {
    resource = resource_provider,
    allocator = machine_allocator,
    buffer = {},
    inflight = {},
    supply_totals = {},
  }

  -- ExecutionContext contract:
  -- - execute_supply/try_start_craft/poll_tasks throw on errors
  -- - supply is non-blocking and only reserves logically (buffer)
  -- - craft is exclusive per machine, allocator controls locks
  -- - context owns transaction boundaries (consume_supplies/commit/rollback)
  function self:execute_supply(step)
    self.buffer[step.item] = (self.buffer[step.item] or 0) + step.count
    self.supply_totals[step.item] = (self.supply_totals[step.item] or 0) + step.count
  end

  local function inputs_available(step)
    for _, input in ipairs(step.recipe.inputs) do
      local need = input.count * step.times
      if (self.buffer[input.item] or 0) < need then
        return false
      end
    end
    return true
  end

  local function consume_inputs(step)
    for _, input in ipairs(step.recipe.inputs) do
      local need = input.count * step.times
      self.buffer[input.item] = (self.buffer[input.item] or 0) - need
      assert(self.buffer[input.item] >= 0, "buffer_negative")
    end
  end

  function self:try_start_craft(step)
    if not inputs_available(step) then
      return false
    end
    local machine = self.allocator:find_compatible(step.recipe)
    if not machine then
      return false
    end
    local handle = machine.provider:start(step.recipe, step.times)
    consume_inputs(step)
    table.insert(self.inflight, { step = step, machine_id = machine.id, provider = machine.provider, handle = handle })
    return true
  end

  function self:poll_tasks()
    local progressed = false
    for i = #self.inflight, 1, -1 do
      local task = self.inflight[i]
      local state = task.provider:poll(task.handle)
      if state == task_state.TaskState.RUNNING then
        -- continue
      elseif state == task_state.TaskState.FAILED then
        self.allocator:unlock(task.machine_id)
        error(task.handle.error or "craft_failed")
      else
        local outputs = task.provider:collect_outputs(task.handle)
        for item, count in pairs(outputs) do
          self.buffer[item] = (self.buffer[item] or 0) + count
          self.resource:add(item, count)
        end
        self.allocator:unlock(task.machine_id)
        table.remove(self.inflight, i)
        progressed = true
      end
    end
    return progressed
  end

  function self:consume_supplies()
    for item, count in pairs(self.supply_totals) do
      self.resource:consume(item, count)
    end
    self.supply_totals = {}
  end

  return self
end

local function run_loop(ctx, plan)
  local ready = {}
  for _, step in ipairs(plan) do
    table.insert(ready, step)
  end

  for _, step in ipairs(plan) do
    if step.kind == "craft" then
      if not ctx.allocator:supports_recipe(step.recipe) then
        error("no_compatible_machine")
      end
    end
  end

  while #ready > 0 or #ctx.inflight > 0 do
    local progressed = false

    local remaining = {}
    for _, step in ipairs(ready) do
      if step.kind == "supply" then
        ctx:execute_supply(step)
        progressed = true
      elseif step.kind == "craft" then
        if ctx:try_start_craft(step) then
          progressed = true
        else
          table.insert(remaining, step)
        end
      else
        error("unknown_step")
      end
    end
    ready = remaining

    local ok = ctx:poll_tasks()
    progressed = progressed or ok

    if not progressed and #ctx.inflight == 0 and #ready > 0 then
      error("deadlock")
    end

    coroutine.yield()
  end

  ctx:consume_supplies()
end

function M.execute(plan, resource_provider, machine_allocator)
  local ctx = M.new(resource_provider, machine_allocator)

  local ok, err = pcall(function()
    run_loop(ctx, plan)
  end)

  if not ok then
    ctx.resource:rollback()
    return false, err
  end

  ctx.resource:commit()
  return true, nil
end

return M
