local assert_equal = require("tests.assert").assert_equal
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local policy = require("runtime.policy")
local multi_storage = require("runtime.multi_storage")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")
local utils = require("tests.test_utils")

local M = {}

local function test_policy_storage_preference()
  local world = virtual_world.new({})
  local function make_provider()
    local task_state = require("runtime.task_state")
    local stock = { ["item:a"] = 1, ["item:b"] = 0 }
    local inflight = {}
    local counter = 0
    return {
      supports = function() return true end,
      prepare = function() end,
      begin = function() end,
      snapshot = function()
        return { ["item:a"] = stock["item:a"], ["item:b"] = stock["item:b"] }
      end,
      get = function(_, item)
        return stock[item] or 0
      end,
      consume = function(_, item, count)
        stock[item] = (stock[item] or 0) - count
      end,
      add = function(_, item, count)
        stock[item] = (stock[item] or 0) + count
      end,
      get_batch_async = function(_, request_map)
        counter = counter + 1
        local id = "req" .. tostring(counter)
        inflight[id] = { items = request_map, state = task_state.TaskState.DONE }
        return id
      end,
      poll_request = function(_, id)
        return inflight[id] and inflight[id].state or task_state.TaskState.FAILED
      end,
      collect_request = function(_, id)
        local req = inflight[id]
        inflight[id] = nil
        for item, count in pairs(req.items or {}) do
          stock[item] = (stock[item] or 0) - count
        end
        return req.items or {}
      end,
      commit = function() end,
      rollback = function() end,
    }
  end

  local s1 = make_provider()
  local s2 = make_provider()

  local p = policy.new({ storage_order = { "s2", "s1" } })
  local resource = multi_storage.new({
    { id = "s1", provider = s1 },
    { id = "s2", provider = s2 },
  }, world.bus, p)

  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, graph_or_err = planner.plan("item:b", 1, recipes_by_output, resource)
  assert_equal(ok, true, "plan ok")

  local provider = virtual_machine.new(world.scheduler, { duration = 1 })
  world:attach_machine("m", provider, "m1")

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph_or_err, resource, world:get_allocator())
    assert_equal(exec_ok, true, err)
  end)

  utils.run_coroutine(world, co, 20)
end

function M.run()
  test_policy_storage_preference()
end

return M
