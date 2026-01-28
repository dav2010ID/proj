local event_bus = require("runtime.event_bus")
local machine_manager = require("runtime.machine_manager")
local machines = require("machines")
local virtual_storage = require("runtime.virtual_storage")
local virtual_scheduler = require("runtime.virtual_scheduler")

local M = {}

function M.new(initial_stock, opts)
  opts = opts or {}
  local bus = event_bus.new()
  local catalog = machines.new_catalog()
  local manager = machine_manager.new(catalog, bus)
  local scheduler = virtual_scheduler.new(bus)
  local storage = virtual_storage.new(initial_stock or {}, bus)

  bus:subscribe("MachineDetected", function(e) manager:on_machine_detected(e) end)
  bus:subscribe("MachineRemoved", function(e) manager:on_machine_removed(e) end)
  bus:subscribe("MachineDisabled", function(e) manager:on_machine_disabled(e) end)
  bus:subscribe("MachineEnabled", function(e) manager:on_machine_enabled(e) end)

  local self = {
    time = 0,
    bus = bus,
    scheduler = scheduler,
    storage = storage,
    manager = manager,
    allocator = nil,
    trace = {},
    trace_limit = opts.trace_limit or 200,
  }

  local function record(event)
    if not event.now then
      event.now = self.time
    end
    table.insert(self.trace, event)
    if #self.trace > self.trace_limit then
      table.remove(self.trace, 1)
    end
  end

  self.bus.on_emit = record

  function self:emit(event)
    self.bus:emit(event)
  end

  function self:tick(steps)
    steps = steps or 1
    for _ = 1, steps do
      self.time = self.time + 1
      self.scheduler:tick()
      self:emit({ type = "Tick", now = self.time })
    end
  end

  function self:attach_machine(machine_type, provider, machine_id)
    self:emit({ type = "MachineDetected", machine_type = machine_type, provider = provider, machine_id = machine_id })
  end

  function self:detach_machine(machine_id)
    self:emit({ type = "MachineRemoved", machine_id = machine_id })
  end

  function self:disable_machine(machine_id)
    self:emit({ type = "MachineDisabled", machine_id = machine_id })
  end

  function self:enable_machine(machine_id)
    self:emit({ type = "MachineEnabled", machine_id = machine_id })
  end

  function self:get_allocator()
    if self.manager.dirty or not self.allocator then
      self.allocator = self.manager:build_allocator()
    end
    return self.allocator
  end

  function self:trace_dump()
    local copy = {}
    for i, event in ipairs(self.trace) do
      copy[i] = event
    end
    return copy
  end

  return self
end

return M
