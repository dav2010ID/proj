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
  local max_items = cap and cap.max_items_per_batch or math.huge
  local max_total = cap and cap.max_total_count or math.huge
  if max_items <= 0 or max_total <= 0 then
    error({ code = errors.BATCH_TOO_LARGE })
  end
  return {
    max_items = max_items,
    max_total = max_total,
  }
end

-- Returns list of batch maps for one storage.
-- Semantics:
-- - max_items_per_batch limits unique item keys in a batch.
-- - max_total_count limits total count across all items.
-- - A single item may be split across multiple batches if needed.
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
    if type(remaining) ~= "number" or remaining <= 0 then
      error({ code = errors.NEGATIVE_COUNT, item = item, count = remaining })
    end
    while remaining > 0 do
      -- Determine how much we can take into the current batch.
      local available = limits.max_total - current_total
      if available <= 0 then
        flush()
        available = limits.max_total
      end
      local take = math.min(remaining, available)

      -- Enforce max unique items per batch.
      if current_items >= limits.max_items and (current[item] == nil) then
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

      if current_total >= limits.max_total then
        flush()
      end
    end
  end

  flush()
  return batches
end

return M

