local machines = require("machines")

local M = {}

function M.new(catalog)
  local self = { catalog = catalog, dirty = false, disabled = {} }

  function self:on_machine_detected(event)
    self.catalog:register(event.machine_type, event.provider, event.machine_id)
    self.disabled[event.machine_id] = nil
    self.dirty = true
  end

  function self:on_machine_removed(event)
    self.catalog:unregister(event.machine_id)
    self.disabled[event.machine_id] = nil
    self.dirty = true
  end

  function self:on_machine_disabled(event)
    self.disabled[event.machine_id] = true
    self.dirty = true
  end

  function self:on_machine_enabled(event)
    self.disabled[event.machine_id] = nil
    self.dirty = true
  end

  function self:build_allocator()
    local active = {}
    for _, machine in ipairs(self.catalog:list_instances()) do
      if not self.disabled[machine.id] then
        table.insert(active, machine)
      end
    end
    self.dirty = false
    return machines.new_allocator(active)
  end

  return self
end

return M
