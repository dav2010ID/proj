local base = require("providers.machine.base")
local machines = require("machines")

local M = {}

function M.new(resource_provider, machine_allocator)
  local self = {
    resource = resource_provider,
    allocator = machine_allocator,
    buffer = {},
    inflight = {},
  }

  function self:execute_supply(step)
    self.resource:consume(step.item, step.count)
    self.buffer[step.item] = (self.buffer[step.item] or 0) + step.count
    return true
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
    end
  end

  function self:execute_craft(step)
    if not inputs_available(step) then
      return false
    end
    local machine = self.allocator:find_compatible(step.recipe)
    if not machine then
      return false
    end
    consume_inputs(step)
    local handle = machine.provider:start(step.recipe, step.times)
    table.insert(self.inflight, { step = step, machine_id = machine.id, provider = machine.provider, handle = handle })
    return true
  end

  function self:poll_tasks()
    local progressed = false
    for i = #self.inflight, 1, -1 do
      local task = self.inflight[i]
      local state = task.provider:poll(task.handle)
      if state == base.TaskState.RUNNING then
        -- continue
      elseif state == base.TaskState.FAILED then
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

  return self
end

function M.execute(plan, resource_provider, machine_allocator)
  local ctx = M.new(resource_provider, machine_allocator)
  local ready = {}
  for _, step in ipairs(plan) do
    table.insert(ready, step)
  end

  for _, step in ipairs(plan) do
    if step.kind == "craft" then
      if not machine_allocator:supports_recipe(step.recipe) then
        return false, "no_compatible_machine"
      end
    end
  end

  while #ready > 0 or #ctx.inflight > 0 do
    local progressed = false

    local remaining = {}
    for _, step in ipairs(ready) do
      local ok = step:execute(ctx)
      if ok then
        progressed = true
      else
        table.insert(remaining, step)
      end
    end
    ready = remaining

    local ok = false
    local status, err = pcall(function()
      ok = ctx:poll_tasks()
    end)
    if not status then
      ctx.resource:rollback()
      return false, err
    end
    progressed = progressed or ok

    if not progressed then
      ctx.resource:rollback()
      return false, "deadlock"
    end
  end

  ctx.resource:commit()
  return true, nil
end

return M
