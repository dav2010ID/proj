local log = require("core.log")
local assert_equal = require("tests.assert").assert_equal
local assert_error = require("tests.test_utils").assert_error_code
local errors = require("core.error_codes")

local M = {}

local function ensure_periphemu()
  if not periphemu or not peripheral then
    log.info("skip test_chest_adapter: periphemu/peripheral unavailable")
    return false
  end
  return true
end

local function cleanup_side(side)
  if periphemu and periphemu.remove then
    pcall(function()
      periphemu.remove(side)
    end)
  end
end

local function new_adapter(side)
  local chest_adapter = require("providers.resource.chest_adapter")
  return chest_adapter.new({ side = side, create = true, double = false })
end

local function clear_chest(adapter)
  local size = adapter.size or 27
  for slot = 1, size do
    pcall(function()
      adapter.chest.setItem(slot, { name = "minecraft:air", item = "minecraft:air", count = 1 })
    end)
  end
end

local function test_chest_adapter_rollback()
  if not ensure_periphemu() then
    return
  end

  local side = "left"
  cleanup_side(side)
  local adapter = new_adapter(side)
  clear_chest(adapter)

  local item = "minecraft:diamond"
  adapter:prepare({ [item] = true })
  adapter:begin()
  adapter:add(item, 5)
  adapter:commit()

  adapter:begin()
  local expected = {}
  for _, entry in pairs(adapter.slots) do
    expected[entry.key] = (expected[entry.key] or 0) + entry.count
  end
  adapter:consume(item, 2)
  adapter:add(item, 1)
  adapter:rollback()

  adapter:begin()
  local snap = adapter:snapshot()
  adapter:commit()
  assert_equal(snap[item] or 0, expected[item] or 0, "rollback restores chest contents")

  cleanup_side(side)
end

local function test_chest_adapter_snapshot_freeze()
  if not ensure_periphemu() then
    return
  end

  local side = "right"
  cleanup_side(side)
  local adapter = new_adapter(side)
  clear_chest(adapter)

  local item = "minecraft:diamond"
  adapter:prepare({ [item] = true })
  adapter:begin()
  adapter:add(item, 1)
  adapter:commit()

  adapter:prepare({ [item] = true })
  adapter:get(item)
  adapter:begin()
  adapter:snapshot()
  local ok, err = pcall(function()
    adapter:consume(item, 1)
  end)
  assert_equal(ok, false, "consume after snapshot should fail")
  assert_error(err, errors.MUTATE_AFTER_SNAPSHOT, "mutate after snapshot")
  adapter:commit()

  cleanup_side(side)
end

function M.run()
  test_chest_adapter_rollback()
  test_chest_adapter_snapshot_freeze()
end

return M
