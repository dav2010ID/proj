local task_state = require("runtime.task_state")
local errors = require("core.error_codes")
local supply_router = require("runtime.supply_router")
local scheduler = require("runtime.scheduler")
local capability = require("core.capability")

local M = {}

function M.new(resource_provider, machine_allocator)
  local self = {
    resource = resource_provider,
    allocator = machine_allocator,
    reserved = {},
    produced = {},
    inflight = {},
    resource_requests = {},
    supply_totals = {},
    batches_dispatched = false,
  }

  -- ExecutionContext contract:
  -- - execute_supply/try_start_craft/poll_tasks throw on errors
  -- - supply is non-blocking and only reserves logically (buffer)
  -- - craft is exclusive per machine, allocator controls locks
  -- - context owns transaction boundaries (consume_supplies/commit/rollback)
  function self:execute_supply(step)
    if self.resource.get_batch_async then
      self.supply_totals[step.item] = (self.supply_totals[step.item] or 0) + step.count
    elseif self.resource.get_async then
      local req_id = self.resource:get_async(step.item, step.count)
      table.insert(self.resource_requests, { id = req_id, item = step.item, count = step.count })
    else
      self.reserved[step.item] = (self.reserved[step.item] or 0) + step.count
      self.supply_totals[step.item] = (self.supply_totals[step.item] or 0) + step.count
    end
  end

  function self:execute_craft(step, started_tick)
    local ok = self:try_start_craft(step, started_tick or 0)
    if not ok then
      error({ code = errors.DEADLOCK })
    end
  end

  local function inputs_available(step)
    for _, input in ipairs(step.recipe.inputs) do
      local need = input.count * step.times
      local available = (self.reserved[input.item] or 0) + (self.produced[input.item] or 0)
      if available < need then
        return false
      end
    end
    return true
  end

  local function consume_inputs(step)
    for _, input in ipairs(step.recipe.inputs) do
      local need = input.count * step.times
      local reserved = self.reserved[input.item] or 0
      local from_reserved = math.min(reserved, need)
      if from_reserved > 0 then
        self.reserved[input.item] = reserved - from_reserved
      end
      local remaining = need - from_reserved
      if remaining > 0 then
        local produced = self.produced[input.item] or 0
        if produced < remaining then
          error({ code = errors.BUFFER_NEGATIVE, item = input.item, need = need })
        end
        self.produced[input.item] = produced - remaining
      end
    end
  end

  function self:try_start_craft(step, started_tick, node_id)
    if not inputs_available(step) then
      return false
    end
    local machine = self.allocator:find_compatible(step.recipe)
    if not machine then
      return false
    end
    local ok, handle_or_err = pcall(function()
      return machine.provider:start(step.recipe, step.times)
    end)
    if not ok then
      self.allocator:unlock(machine.id)
      error(handle_or_err)
    end
    local ok_consume, consume_err = pcall(function()
      consume_inputs(step)
    end)
    if not ok_consume then
      self.allocator:unlock(machine.id)
      error(consume_err)
    end
    table.insert(self.inflight, {
      step = step,
      machine_id = machine.id,
      provider = machine.provider,
      handle = handle_or_err,
      started_tick = started_tick,
      node_id = node_id,
    })
    return true
  end

  function self:poll_tasks(on_complete)
    local progressed = false
    for i = #self.inflight, 1, -1 do
      local task = self.inflight[i]
      local state = task.provider:poll(task.handle)
      if state == task_state.TaskState.RUNNING then
        -- continue
      elseif state == task_state.TaskState.FAILED then
        self.allocator:unlock(task.machine_id)
        error(task.handle.error or { code = errors.CRAFT_FAILED })
      else
        local outputs = task.provider:collect_outputs(task.handle)
        for item, count in pairs(outputs) do
          self.produced[item] = (self.produced[item] or 0) + count
        end
        self.allocator:unlock(task.machine_id)
        table.remove(self.inflight, i)
        progressed = true
        if on_complete then
          on_complete(task)
        end
      end
    end
    return progressed
  end

  function self:poll_resource_requests()
    if not self.resource.poll_request then
      return false
    end
    local progressed = false
    for i = #self.resource_requests, 1, -1 do
      local r = self.resource_requests[i]
      local state = self.resource:poll_request(r.id)
      if state == task_state.TaskState.RUNNING then
        -- wait
      elseif state == task_state.TaskState.FAILED then
        error({ code = errors.RESOURCE_FAILED, item = r.item })
      else
        local result = self.resource:collect_request(r.id)
        if type(result) == "table" then
          for item, count in pairs(result) do
            self.reserved[item] = (self.reserved[item] or 0) + count
          end
        else
          self.reserved[r.item] = (self.reserved[r.item] or 0) + r.count
        end
        table.remove(self.resource_requests, i)
        progressed = true
      end
    end
    return progressed
  end

  function self:dispatch_supply_batches()
    if not self.resource.get_batch_async then
      return
    end
    if self.batches_dispatched then
      return
    end
    if next(self.supply_totals) == nil then
      return
    end
    local caps = capability.get_capability_limits(self.resource, "batch")
    local batches = supply_router.split_batches(self.supply_totals, caps)
    for _, batch in ipairs(batches) do
      local req_id = self.resource:get_batch_async(batch)
      table.insert(self.resource_requests, { id = req_id, batch = true })
    end
    self.batches_dispatched = true
  end

  function self:consume_supplies()
    if self.resource_requests and #self.resource_requests > 0 then
      return
    end
    if self.resource.get_batch_async then
      self.supply_totals = {}
      return
    end
    for item, count in pairs(self.supply_totals) do
      self.resource:consume(item, count)
    end
    self.supply_totals = {}
  end

  function self:apply_outputs()
    for item, count in pairs(self.produced) do
      if count > 0 then
        self.resource:add(item, count)
      end
    end
    self.produced = {}
    self.reserved = {}
    self.resource_requests = {}
    self.batches_dispatched = false
  end

  return self
end

local function run_loop(ctx, plan, max_steps_per_tick, task_timeout)
  local ready = {}
  for _, step in ipairs(plan) do
    table.insert(ready, step)
  end
  local tick = 0

  for _, step in ipairs(plan) do
    if step.kind == "craft" then
      if not ctx.allocator:supports_recipe(step.recipe) then
        error({ code = errors.NO_COMPATIBLE_MACHINE })
      end
    end
  end

  while #ready > 0 or #ctx.inflight > 0 do
    tick = tick + 1
    local progressed = false

    local processed = 0
    local remaining = {}
    for _, step in ipairs(ready) do
      if max_steps_per_tick and max_steps_per_tick > 0 and processed >= max_steps_per_tick then
        table.insert(remaining, step)
      else
        if step.kind == "supply" then
          ctx:execute_supply(step)
          progressed = true
        elseif step.kind == "craft" then
          if ctx:try_start_craft(step, tick) then
            progressed = true
          else
            table.insert(remaining, step)
          end
        else
          error({ code = errors.UNKNOWN_STEP })
        end
        processed = processed + 1
      end
    end
    ready = remaining

    ctx:dispatch_supply_batches()
    local ok_resources = ctx:poll_resource_requests()
    local ok = ctx:poll_tasks()
    progressed = progressed or ok or ok_resources

    if task_timeout then
      for _, task in ipairs(ctx.inflight) do
        if task.started_tick and (tick - task.started_tick) >= task_timeout then
          error({ code = errors.TASK_TIMEOUT, task_id = task.handle and task.handle.id })
        end
      end
    end

    if not progressed and #ctx.inflight == 0 and #ready > 0 and #ctx.resource_requests == 0 then
      error({ code = errors.DEADLOCK })
    end

    local running, is_main = coroutine.running()
    if running and (is_main == false or is_main == nil) then
      coroutine.yield()
    end
  end

  ctx:consume_supplies()
  ctx:apply_outputs()
end

local function run_graph_loop(ctx, graph, max_steps_per_tick, task_timeout)
  local state = scheduler.schedule(graph, {})
  local tick = 0

  for _, node in ipairs(graph.nodes) do
    if node.kind == "craft" then
      if not ctx.allocator:supports_recipe(node.recipe) then
        error({ code = errors.NO_COMPATIBLE_MACHINE })
      end
    end
  end

  while (not scheduler.all_done(state)) or #ctx.inflight > 0 do
    tick = tick + 1
    local progressed = false

    local processed = 0
    local ready = scheduler.get_ready_tasks(state)
    for _, task in ipairs(ready) do
      if max_steps_per_tick and max_steps_per_tick > 0 and processed >= max_steps_per_tick then
        break
      end
      local node = task.node
      if node.kind == "supply" then
        ctx:execute_supply(node)
        scheduler.mark_started(state, task)
        scheduler.update_after_completion(task, state)
        progressed = true
      elseif node.kind == "craft" then
        if ctx:try_start_craft(node, tick, task.id) then
          scheduler.mark_started(state, task)
          progressed = true
        end
      else
        error({ code = errors.UNKNOWN_STEP })
      end
      processed = processed + 1
    end

    ctx:dispatch_supply_batches()
    local ok_resources = ctx:poll_resource_requests()
    local ok = ctx:poll_tasks(function(task)
      if task.node_id then
        scheduler.update_after_completion({ id = task.node_id }, state)
      end
    end)
    progressed = progressed or ok or ok_resources

    if task_timeout then
      for _, task in ipairs(ctx.inflight) do
        if task.started_tick and (tick - task.started_tick) >= task_timeout then
          error({ code = errors.TASK_TIMEOUT, task_id = task.handle and task.handle.id })
        end
      end
    end

    if not progressed and #ctx.inflight == 0 and (not scheduler.all_done(state)) and #ctx.resource_requests == 0 then
      error({ code = errors.DEADLOCK })
    end

    local running, is_main = coroutine.running()
    if running and (is_main == false or is_main == nil) then
      coroutine.yield()
    end
  end

  ctx:consume_supplies()
  ctx:apply_outputs()
end

local function is_graph(plan)
  return type(plan) == "table"
    and type(plan.nodes) == "table"
    and type(plan.edges) == "table"
    and type(plan.get_dependencies) == "function"
end

function M.execute(plan, resource_provider, machine_allocator, opts)
  local ctx = M.new(resource_provider, machine_allocator)
  local max_steps_per_tick = opts and opts.max_steps_per_tick or 1
  local task_timeout = opts and opts.task_timeout

  if resource_provider.begin then
    resource_provider:begin()
  end

  local ok, err = pcall(function()
    if is_graph(plan) then
      run_graph_loop(ctx, plan, max_steps_per_tick, task_timeout)
    else
      run_loop(ctx, plan, max_steps_per_tick, task_timeout)
    end
  end)

  if not ok then
    for _, task in ipairs(ctx.inflight) do
      pcall(function()
        ctx.allocator:unlock(task.machine_id)
      end)
    end
    ctx.resource:rollback()
    return false, err
  end

  ctx.resource:commit()
  return true, nil
end

return M


