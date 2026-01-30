local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local planner = require("core.planner")
local recipe = require("core.recipe")
local executor = require("runtime.executor")
local virtual_world = require("virtual.world")
local virtual_async_storage = require("virtual.async_storage")
local multi_storage = require("runtime.multi_storage")
local errors = require("core.error_codes")

local M = {}

local function test_two_storages_one_failed()
  local world = virtual_world.new({})
  local s1 = virtual_async_storage.new(world.scheduler, { ["item:a"] = 1 }, 2)
  local s2 = {
    data = { ["item:b"] = 1 },
    supports = function(self, item)
      return item == "item:b"
    end,
    prepare = function() end,
    begin = function() end,
    snapshot = function(self)
      return { ["item:b"] = self.data["item:b"] or 0 }
    end,
    get = function(self, item)
      return self.data[item] or 0
    end,
    get_batch_async = function()
      return "fail_req"
    end,
    poll_request = function()
      return require("runtime.task_state").TaskState.FAILED
    end,
    collect_request = function()
      error("should not collect failed request")
    end,
    commit = function() end,
    rollback = function() end,
  }
  s1:set_supported_items({ "item:a" })

  local resource = multi_storage.new({
    { id = "s1", provider = s1 },
    { id = "s2", provider = s2 },
  }, world.bus)

  local registry = recipe.new_registry()
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, graph_or_err = planner.plan("item:b", 1, recipes_by_output, resource)
  assert_equal(ok, true, "plan ok")

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph_or_err, resource, world:get_allocator())
    if exec_ok then
      error("expected failure")
    end
    assert(err ~= nil, "expected error")
    assert_equal(err.code, errors.RESOURCE_FAILED, "resource failed")
  end)

  utils.run_coroutine(world, co, 20)
end

function M.run()
  test_two_storages_one_failed()
end

return M

