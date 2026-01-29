local assert_equal = require("tests.assert").assert_equal
local assert_error = require("tests.test_utils").assert_error_code
local task_state = require("runtime.task_state")
local errors = require("core.error_codes")
local scheduler_module = require("virtual.scheduler")
local chest_adapter = require("providers.resource.chest_adapter")

local M = {}

local function new_inventory(name, size, registry, slots)
  local self = {
    name = name,
    size = size or 27,
    slots = slots or {},
  }

  function self:list()
    local copy = {}
    for slot, entry in pairs(self.slots) do
      copy[slot] = { name = entry.name, count = entry.count }
    end
    return copy
  end

  local function put_item(slot, item, count)
    if self.slots[slot] then
      local existing = self.slots[slot]
      if existing.name ~= item then
        return false
      end
      existing.count = existing.count + count
      return true
    end
    self.slots[slot] = { name = item, count = count }
    return true
  end

  local function take_item(slot, count)
    local entry = self.slots[slot]
    if not entry then
      return 0, nil
    end
    local take = math.min(entry.count, count)
    entry.count = entry.count - take
    if entry.count <= 0 then
      self.slots[slot] = nil
    end
    return take, entry.name
  end

  local function find_target_slot(item, desired_slot)
    if desired_slot and desired_slot >= 1 and desired_slot <= self.size then
      if not self.slots[desired_slot] or self.slots[desired_slot].name == item then
        return desired_slot
      end
    end
    for slot = 1, self.size do
      if not self.slots[slot] or self.slots[slot].name == item then
        return slot
      end
    end
    return nil
  end

  function self:pushItems(target_name, from_slot, limit, to_slot)
    local target = registry[target_name]
    if not target then
      return 0
    end
    local entry = self.slots[from_slot]
    if not entry then
      return 0
    end
    local count = math.min(entry.count, limit or entry.count)
    local moved, item = take_item(from_slot, count)
    if moved <= 0 then
      return 0
    end
    local dest_slot = find_target_slot(item, to_slot)
    if not dest_slot then
      put_item(from_slot, item, moved)
      return 0
    end
    target:receive(dest_slot, item, moved)
    return moved
  end

  function self:pullItems(source_name, from_slot, limit, to_slot)
    local source = registry[source_name]
    if not source then
      return 0
    end
    return source:pushItems(self.name, from_slot, limit, to_slot)
  end

  function self:receive(slot, item, count)
    return put_item(slot, item, count)
  end

  registry[name] = self
  return self
end

local function test_chest_adapter_get_and_supports()
  local registry = {}
  local chest = new_inventory("chest", 9, registry, {
    [1] = { name = "item:oak", count = 4 },
    [2] = { name = "item:birch", count = 2 },
  })
  local buffer = new_inventory("buffer", 9, registry, {})
  local scheduler = scheduler_module.new()
  local adapter = chest_adapter.new(chest, scheduler, {
    buffer_name = buffer.name,
    input_peripheral = buffer,
  })

  assert_equal(adapter:get("item:oak"), 4, "get returns oak count")
  assert_equal(adapter:supports("item:oak"), true, "supports existing item")
  assert_equal(adapter:supports("item:stone"), false, "supports missing item")
end

local function test_chest_adapter_batch_pull()
  local registry = {}
  local chest = new_inventory("chest", 9, registry, {
    [1] = { name = "item:oak", count = 4 },
    [2] = { name = "item:birch", count = 2 },
  })
  local buffer = new_inventory("buffer", 9, registry, {})
  local scheduler = scheduler_module.new()
  local adapter = chest_adapter.new(chest, scheduler, {
    buffer_name = buffer.name,
    input_peripheral = buffer,
  })

  local req_id = adapter:get_batch_async({ ["item:oak"] = 3, ["item:birch"] = 2 })
  assert_equal(adapter:poll_request(req_id), task_state.TaskState.RUNNING, "batch starts running")
  scheduler:tick()
  assert_equal(adapter:poll_request(req_id), task_state.TaskState.DONE, "batch completes")
  local result = adapter:collect_request(req_id)
  assert_equal(result["item:oak"], 3, "oak moved")
  assert_equal(result["item:birch"], 2, "birch moved")
  assert_equal(adapter:get("item:oak"), 1, "oak remaining")
  assert_equal(adapter:get("item:birch"), 0, "birch remaining")
end

local function test_chest_adapter_add_from_buffer()
  local registry = {}
  local chest = new_inventory("chest", 9, registry, {})
  local buffer = new_inventory("buffer", 9, registry, {
    [1] = { name = "item:oak", count = 2 },
  })
  local scheduler = scheduler_module.new()
  local adapter = chest_adapter.new(chest, scheduler, {
    buffer_name = buffer.name,
    input_peripheral = buffer,
  })

  adapter:add("item:oak", 2)
  assert_equal(adapter:get("item:oak"), 2, "oak added to chest")
end

local function test_chest_adapter_insufficient_stock()
  local registry = {}
  local chest = new_inventory("chest", 9, registry, {
    [1] = { name = "item:oak", count = 1 },
  })
  local buffer = new_inventory("buffer", 9, registry, {})
  local scheduler = scheduler_module.new()
  local adapter = chest_adapter.new(chest, scheduler, {
    buffer_name = buffer.name,
    input_peripheral = buffer,
  })

  local req_id = adapter:get_batch_async({ ["item:oak"] = 2 })
  scheduler:tick()
  assert_equal(adapter:poll_request(req_id), task_state.TaskState.FAILED, "batch fails on stock")
  local ok, err = pcall(function()
    adapter:collect_request(req_id)
  end)
  assert_equal(ok, false, "collect_request fails on failed request")
  assert_error(err, errors.REQUEST_NOT_DONE, "request not done")
end

local function test_chest_adapter_from_periphemu()
  local registry = {}
  local chest = new_inventory("left", 9, registry, {
    [1] = { name = "item:oak", count = 1 },
  })
  local buffer = new_inventory("buffer", 9, registry, {})
  local scheduler = scheduler_module.new()
  local created = {}
  local wrapped = {}

  local periphemu = {
    create = function(side, ptype)
      created.side = side
      created.ptype = ptype
      print("use internnal")
    end,
  }

  local peripheral_api = {
    wrap = function(name)
      wrapped[name] = (wrapped[name] or 0) + 1
      return registry[name]
    end,
  }

  local adapter = chest_adapter.from_periphemu(periphemu, peripheral_api, scheduler, {
    side = "left",
    peripheral_type = "minecraft:chest",
    input_name = buffer.name,
  })

  assert_equal(created.side, "left", "periphemu side used")
  assert_equal(created.ptype, "minecraft:chest", "periphemu type used")
  assert_equal(wrapped.left, 1, "chest wrapped")
  assert_equal(wrapped.buffer, 1, "input wrapped")
  assert_equal(adapter:get("item:oak"), 1, "adapter works with periphemu chest")
end

function M.run()
  test_chest_adapter_get_and_supports()
  test_chest_adapter_batch_pull()
  test_chest_adapter_add_from_buffer()
  test_chest_adapter_insufficient_stock()
  test_chest_adapter_from_periphemu()
end

return M
