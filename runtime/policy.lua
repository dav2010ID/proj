local M = {}

function M.new(rules)
  local self = {
    rules = rules or {},
  }

  function self:select_storage(item, providers)
    local rules = self.rules or {}
    local prefer = nil
    if rules.storage_preference and rules.storage_preference[item] then
      prefer = rules.storage_preference[item]
    elseif rules.storage_order then
      prefer = rules.storage_order
    end
    if prefer then
      for _, id in ipairs(prefer) do
        for _, entry in ipairs(providers or {}) do
          if entry.id == id then
            local provider = entry.provider
            if not provider.supports or provider:supports(item) then
              return entry
            end
          end
        end
      end
    end
    for _, entry in ipairs(providers or {}) do
      local provider = entry.provider
      if not provider.supports or provider:supports(item) then
        return entry
      end
    end
    return nil
  end

  function self:select_machine(recipe, allocator)
    local rules = self.rules or {}
    if rules.machine_order then
      local machine = allocator:find_compatible_with_policy(recipe, { machine_order = rules.machine_order })
      if machine then
        return machine
      end
    end
    if rules.machine_type_order then
      local machine = allocator:find_compatible_with_policy(recipe, { machine_type_order = rules.machine_type_order })
      if machine then
        return machine
      end
    end
    return allocator:find_compatible(recipe)
  end

  function self:ready_limit()
    local rules = self.rules or {}
    return rules.max_ready_per_tick
  end

  return self
end

return M
