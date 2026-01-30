-- TEST SUPPORT CODE
-- Not used in production.
local event_bus = require("runtime.event_bus")
local machine_manager = require("runtime.machine_manager")
local storage_manager = require("runtime.storage_manager")
local multi_storage = require("runtime.multi_storage")
local machines = require("machines")
local virtual_storage = require("virtual.storage")
local virtual_scheduler = require("virtual.scheduler")
local virtual_async_storage = require("virtual.async_storage")
local events = require("core.events")

local M = {}

function M.new(initial_stock, opts)
  opts = opts or {}
  local bus = event_bus.new()
  local catalog = machines.new_catalog()
  local manager = machine_manager.new(catalog, bus)
  local scheduler = virtual_scheduler.new(bus)
  local storage
  if opts.async_storage then
    storage = virtual_async_storage.new(scheduler, initial_stock or {}, opts.storage_delay or 2)
  else
    storage = virtual_storage.new(initial_stock or {}, bus)
  end
  local storage_mgr = storage_manager.new(storage, bus)

  bus:subscribe("MachineDetected", function(e) manager:on_machine_detected(e) end)
  bus:subscribe("MachineRemoved", function(e) manager:on_machine_removed(e) end)
  bus:subscribe("MachineDisabled", function(e) manager:on_machine_disabled(e) end)
  bus:subscribe("MachineEnabled", function(e) manager:on_machine_enabled(e) end)
  bus:subscribe("StorageDetected", function(e) storage_mgr:on_storage_detected(e) end)
  bus:subscribe("StorageRemoved", function(e) storage_mgr:on_storage_removed(e) end)
  bus:subscribe("StorageDisabled", function(e) storage_mgr:on_storage_disabled(e) end)
  bus:subscribe("StorageEnabled", function(e) storage_mgr:on_storage_enabled(e) end)

  local self = {
    time = 0,
    bus = bus,
    scheduler = scheduler,
    storage = storage_mgr,
    manager = manager,
    storage_manager = storage_mgr,
    allocator = nil,
    storage_entries = {},
    storage_disabled = {},
    legacy_storage_attached = false,
    trace = {},
    trace_limit = opts.trace_limit or 200,
  }

  local function record(event)
    local now = event.now or self.time
    local payload = {}
    for k, v in pairs(event) do
      if k ~= "now" and k ~= "type" then
        payload[k] = v
      end
    end
    table.insert(self.trace, { type = event.type, now = now, payload = payload })
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
      self:emit(events.Tick({ now = self.time }))
    end
  end

  function self:attach_machine(machine_type, provider, machine_id)
    if self.manager.catalog.instances[machine_id] then
      error("machine already attached: " .. tostring(machine_id))
    end
    self:emit(events.MachineDetected({ machine_type = machine_type, provider = provider, machine_id = machine_id }))
  end

  local function build_storage_provider()
    local active = {}
    for id, entry in pairs(self.storage_entries) do
      if not self.storage_disabled[id] then
        table.insert(active, { id = id, provider = entry.provider })
      end
    end
    if #active == 0 then
      return nil
    end
    if #active == 1 then
      return active[1].provider
    end
    return multi_storage.new(active, self.bus, opts.policy)
  end

  function self:attach_storage(storage, id)
    if id == nil then
      if self.legacy_storage_attached then
        error("storage already attached")
      end
      self.legacy_storage_attached = true
      self:emit(events.StorageDetected({ provider = storage }))
      return
    end
    if self.storage_entries[id] then
      error("storage already attached: " .. tostring(id))
    end
    self.storage_entries[id] = { provider = storage }
    local provider = build_storage_provider()
    if provider then
      self:emit(events.StorageDetected({ provider = provider, storage_id = id }))
    else
      self:emit(events.StorageRemoved({ storage_id = id }))
    end
  end

  function self:detach_storage(id)
    if id == nil then
      if not self.legacy_storage_attached then
        error("no storage attached")
      end
      self.legacy_storage_attached = false
      self:emit(events.StorageRemoved({}))
      return
    end
    if not self.storage_entries[id] then
      error("storage not attached: " .. tostring(id))
    end
    self.storage_entries[id] = nil
    self.storage_disabled[id] = nil
    local provider = build_storage_provider()
    if provider then
      self:emit(events.StorageDetected({ provider = provider, storage_id = id }))
    else
      self:emit(events.StorageRemoved({ storage_id = id }))
    end
  end

  function self:disable_storage(id)
    if id == nil then
      self:emit(events.StorageDisabled({}))
      return
    end
    if not self.storage_entries[id] then
      error("storage not attached: " .. tostring(id))
    end
    self.storage_disabled[id] = true
    local provider = build_storage_provider()
    if provider then
      self:emit(events.StorageDetected({ provider = provider, storage_id = id }))
    else
      self:emit(events.StorageRemoved({ storage_id = id }))
    end
  end

  function self:enable_storage(id)
    if id == nil then
      self:emit(events.StorageEnabled({}))
      return
    end
    if not self.storage_entries[id] then
      error("storage not attached: " .. tostring(id))
    end
    self.storage_disabled[id] = nil
    local provider = build_storage_provider()
    if provider then
      self:emit(events.StorageDetected({ provider = provider, storage_id = id }))
    else
      self:emit(events.StorageRemoved({ storage_id = id }))
    end
  end

  function self:detach_machine(machine_id)
    if not self.manager.catalog.instances[machine_id] then
      error("machine not attached: " .. tostring(machine_id))
    end
    self:emit(events.MachineRemoved({ machine_id = machine_id }))
  end

  function self:disable_machine(machine_id)
    if not self.manager.catalog.instances[machine_id] then
      error("machine not attached: " .. tostring(machine_id))
    end
    self:emit(events.MachineDisabled({ machine_id = machine_id }))
  end

  function self:enable_machine(machine_id)
    if not self.manager.catalog.instances[machine_id] then
      error("machine not attached: " .. tostring(machine_id))
    end
    self:emit(events.MachineEnabled({ machine_id = machine_id }))
  end

  function self:get_allocator()
    if self.manager.dirty or not self.allocator then
      -- Allocator cache depends only on machine state.
      self.allocator = self.manager:build_allocator()
    end
    return self.allocator
  end

  function self:assert_no_inflight_tasks()
    local count = 0
    for _ in pairs(self.scheduler.tasks or {}) do
      count = count + 1
    end
    if self.storage and self.storage.inflight_count then
      count = count + self.storage:inflight_count()
    end
    if count > 0 then
      error("inflight tasks: " .. tostring(count))
    end
  end

  function self:assert_idle()
    self:assert_no_inflight_tasks()
    if self.scheduler and self.scheduler.timers and #self.scheduler.timers > 0 then
      error("pending timers: " .. tostring(#self.scheduler.timers))
    end
  end

  function self:assert_trace_contains(event_type, matcher)
    for _, ev in ipairs(self.trace) do
      if ev.type == event_type and (not matcher or matcher(ev.payload or {})) then
        return true
      end
    end
    error("trace missing event: " .. tostring(event_type))
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

