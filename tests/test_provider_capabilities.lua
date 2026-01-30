local assert_equal = require("tests.assert").assert_equal
local capability = require("core.capability")
local memory_resource = require("providers.resource.memory")
local virtual_storage = require("virtual.storage")
local virtual_async_storage = require("virtual.async_storage")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")
local crafting_table = require("providers.machine.crafting_table")
local mechanical_crafter = require("providers.machine.mechanical_crafter")
local multi_storage = require("runtime.multi_storage")
local chest_adapter = require("providers.resource.chest_adapter")

local M = {}

local function assert_provider(provider, label)
  local ok = capability.validate_provider(provider)
  assert_equal(ok, true, "capabilities valid: " .. tostring(label))
end

local function test_provider_capabilities()
  local world = virtual_world.new({})

  assert_provider(memory_resource.new({}), "memory")
  assert_provider(virtual_storage.new({}, world.bus), "virtual_storage")
  assert_provider(virtual_async_storage.new(world.scheduler, {}, 1), "virtual_async_storage")
  assert_provider(multi_storage.new({}, world.bus), "multi_storage")

  assert_provider(crafting_table.new(), "crafting_table")
  assert_provider(mechanical_crafter.new(), "mechanical_crafter")
  assert_provider(virtual_machine.new(world.scheduler, {}), "virtual_machine")

  if periphemu and peripheral then
    local ok, provider = pcall(function()
      return chest_adapter.new({ side = "left", create = false })
    end)
    if ok and provider then
      assert_provider(provider, "chest_adapter")
    end
  end
end

function M.run()
  test_provider_capabilities()
end

return M
