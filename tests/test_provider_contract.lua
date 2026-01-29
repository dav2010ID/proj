local provider_contract = require("tests.provider_contract")
local virtual_machine = require("virtual.machine")

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

function M.run()
  test_provider_contract_virtual_machine()
end

return M

