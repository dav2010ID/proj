-- Runtime manager
-- Coordinates machines via events; not business logic.
local machines = require("machines")

local M = {}

function M.new(catalog, bus)
  local self = { catalog = catalog, dirty = false, disabled = {}, removed = {}, bus = bus }

  function self:on_machine_detected(event)
    if self.catalog.instances[event.machine_id] then
      error("machine already registered: " .. tostring(event.machine_id))
    end
    self.catalog:register(event.machine_type, event.provider, event.machine_id)
    self.disabled[event.machine_id] = nil
    self.removed[event.machine_id] = nil
    self.dirty = true
  end

  function self:on_machine_removed(event)
    -- removed != disabled; removed means pending unregister
    self.removed[event.machine_id] = true
    self.dirty = true
  end

  function self:on_machine_disabled(event)
    if self.removed[event.machine_id] then
      return
    end
    self.disabled[event.machine_id] = true
    self.dirty = true
  end

  function self:on_machine_enabled(event)
    if self.removed[event.machine_id] then
      return
    end
    self.disabled[event.machine_id] = nil
    self.dirty = true
  end

  function self:build_allocator()
    -- Cleanup removed machines on allocator rebuild.
    self:cleanup_removed()
    local active = {}
    for _, machine in ipairs(self.catalog:list_instances()) do
      if not self.disabled[machine.id] and not self.removed[machine.id] then
        table.insert(active, machine)
      end
    end
    self.dirty = false
    return machines.new_allocator(active, self.bus)
  end

  function self:cleanup_removed()
    local removed_any = false
    for machine_id, _ in pairs(self.removed) do
      self.catalog:unregister(machine_id)
      self.removed[machine_id] = nil
      self.disabled[machine_id] = nil
      removed_any = true
    end
    if removed_any then
      self.dirty = true
    end
  end

  return self
end

return M

