local provider_contract = require("tests.provider_contract")
local virtual_machine = require("virtual.machine")
local crafting_table = require("providers.machine.crafting_table")
local mechanical_crafter = require("providers.machine.mechanical_crafter")

local M = {}

local function test_provider_contract_virtual_machine()
  local recipe = {
    id = "contract_recipe",
    inputs = {},
    outputs = { { item = "item:o", count = 1 } },
    machine = "m",
  }
  provider_contract.run_contract(function(_, scheduler)
    return virtual_machine.new(scheduler, { duration = 2 })
  end, recipe)
end

local function test_provider_contract_crafting_table()
  local recipe = {
    id = "ct_recipe",
    inputs = {},
    outputs = { { item = "item:o", count = 1 } },
    machine = "crafting_table",
  }
  provider_contract.run_contract(function()
    return crafting_table.new()
  end, recipe)
end

local function test_provider_contract_mechanical_crafter()
  local recipe = {
    id = "mc_recipe",
    inputs = {},
    outputs = { { item = "item:o", count = 1 } },
    machine = "mechanical_crafter",
  }
  provider_contract.run_contract(function()
    return mechanical_crafter.new()
  end, recipe)
end

function M.run()
  test_provider_contract_virtual_machine()
  test_provider_contract_crafting_table()
  test_provider_contract_mechanical_crafter()
end

return M

