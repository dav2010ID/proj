local errors = require("core.error_codes")

local M = {}

local function sort_keys(map)
  local keys = {}
  for k, _ in pairs(map) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

local function capacity_limits(cap)
  return {
    max_items = cap and cap.max_items_per_batch or nil,
    max_total = cap and cap.max_total_count or nil,
  }
end

-- Returns list of batch maps for one storage.
function M.split_batches(request_map, cap)
  local limits = capacity_limits(cap)
  local keys = sort_keys(request_map)
  local batches = {}
  local current = {}
  local current_items = 0
  local current_total = 0

  local function flush()
    if current_items > 0 then
      table.insert(batches, current)
      current = {}
      current_items = 0
      current_total = 0
    end
  end

  for _, item in ipairs(keys) do
    local remaining = request_map[item]
    while remaining > 0 do
      local take = remaining
      if limits.max_total then
        local available = limits.max_total - current_total
        if available <= 0 then
          flush()
          available = limits.max_total
        end
        if take > available then
          take = available
        end
      end

      if limits.max_items and current_items >= limits.max_items and (current[item] == nil) then
        flush()
      end

      if take <= 0 then
        error({ code = errors.BATCH_TOO_LARGE, item = item })
      end

      if current[item] == nil then
        current_items = current_items + 1
      end
      current[item] = (current[item] or 0) + take
      current_total = current_total + take
      remaining = remaining - take

      if limits.max_total and current_total >= limits.max_total then
        flush()
      end
      if limits.max_items and current_items >= limits.max_items then
        -- flush only if another distinct item remains
        -- in this loop, remaining might be > 0 for same item; keep in same batch if possible
      end
    end
  end

  flush()
  return batches
end

return M
