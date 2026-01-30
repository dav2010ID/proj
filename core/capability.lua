local M = {}

local function is_positive_number(value)
  return type(value) == "number" and value > 0
end

function M.validate(capabilities)
  if type(capabilities) ~= "table" then
    return false, "capabilities must be table"
  end
  if capabilities.batch ~= nil and type(capabilities.batch) ~= "table" then
    return false, "batch must be table or nil"
  end
  if capabilities.batch then
    if capabilities.batch.max_items ~= nil and not is_positive_number(capabilities.batch.max_items) then
      return false, "batch.max_items must be > 0"
    end
    if capabilities.batch.max_total ~= nil and not is_positive_number(capabilities.batch.max_total) then
      return false, "batch.max_total must be > 0"
    end
  end
  for _, key in ipairs({ "async", "parallel", "transactional" }) do
    if capabilities[key] ~= nil and type(capabilities[key]) ~= "boolean" then
      return false, key .. " must be boolean"
    end
  end
  return true, nil
end

function M.validate_provider(provider)
  if type(provider) ~= "table" then
    return false, "provider must be table"
  end
  if type(provider.capabilities) ~= "table" then
    return false, "provider.capabilities must be table"
  end
  return M.validate(provider.capabilities)
end

function M.has_capability(provider, cap_name)
  if type(provider) ~= "table" then
    return false
  end
  local caps = provider.capabilities
  if type(caps) ~= "table" then
    return false
  end
  if cap_name == "batch" then
    return type(caps.batch) == "table"
  end
  return caps[cap_name] == true
end

local function normalize_batch(cap)
  if not cap then
    return {}
  end
  local max_items = cap.max_items or cap.max_items_per_batch
  local max_total = cap.max_total or cap.max_total_count
  return {
    max_items_per_batch = max_items,
    max_total_count = max_total,
  }
end

function M.get_capability_limits(provider, cap_name)
  if cap_name ~= "batch" then
    if type(provider) == "table" and type(provider.capabilities) == "table" then
      return provider.capabilities[cap_name]
    end
    return nil
  end

  if type(provider) == "table" then
    if type(provider.capabilities) == "table" then
      return normalize_batch(provider.capabilities.batch)
    end
    if type(provider.capabilities) == "function" then
      return normalize_batch(provider:capabilities())
    end
  end

  if type(provider) == "table" and (provider.max_items_per_batch or provider.max_total_count) then
    return normalize_batch(provider)
  end

  return {}
end

return M
