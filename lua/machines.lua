local errors = require("core.error_codes")

local M = {}

function M.new(machine_id, machine_type, provider, state)
  return {
    id = machine_id,
    type = machine_type,
    provider = provider,
    state = state or { circuit = nil, mode = nil },
  }
end

function M.new_allocator(machines, bus)
  local self = { free = {}, busy = {}, bus = bus }
  for _, m in ipairs(machines) do
    self.free[m.id] = m
  end

  function self:lock(machine_type)
    for id, machine in pairs(self.free) do
      if machine.type == machine_type then
        assert(self.busy[id] == nil)
        self.free[id] = nil
        self.busy[id] = machine
        if self.bus then
          self.bus:emit({ type = "MachineLocked", machine_id = id, machine_type = machine.type })
        end
        return machine
      end
    end
    return nil
  end

  function self:unlock(machine_id)
    if not self.busy[machine_id] then
      error({ code = "UNLOCK_NON_BUSY", machine_id = machine_id })
    end
    local machine = self.busy[machine_id]
    self.busy[machine_id] = nil
    self.free[machine.id] = machine
    if self.bus then
      self.bus:emit({ type = "MachineUnlocked", machine_id = machine.id, machine_type = machine.type })
    end
  end

  function self:supports(machine_type)
    for _, machine in pairs(self.free) do
      if machine.type == machine_type then
        return true
      end
    end
    for _, machine in pairs(self.busy) do
      if machine.type == machine_type then
        return true
      end
    end
    return false
  end

  function self:find_compatible(recipe)
    for id, machine in pairs(self.free) do
      if machine.type == recipe.machine and machine.provider:can_craft(recipe, machine) then
        assert(self.busy[id] == nil)
        self.free[id] = nil
        self.busy[id] = machine
        return machine
      end
    end
    return nil
  end

  function self:supports_recipe(recipe)
    for _, machine in pairs(self.free) do
      if machine.type == recipe.machine and machine.provider:can_craft(recipe, machine) then
        return true
      end
    end
    for _, machine in pairs(self.busy) do
      if machine.type == recipe.machine and machine.provider:can_craft(recipe, machine) then
        return true
      end
    end
    return false
  end

  return self
end

function M.new_catalog()
  local self = { instances = {} }

  function self:register(machine_type, provider, machine_id)
    self.instances[machine_id] = M.new(machine_id, machine_type, provider)
  end

  function self:unregister(machine_id)
    self.instances[machine_id] = nil
  end

  function self:list_instances()
    local items = {}
    for _, inst in pairs(self.instances) do
      table.insert(items, inst)
    end
    return items
  end

  function self:build_allocator(bus)
    return M.new_allocator(self:list_instances(), bus)
  end

  return self
end

return M


