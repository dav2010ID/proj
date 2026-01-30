local M = {}

local counter = 0

local function next_id()
  counter = counter + 1
  return tostring(counter)
end

local function now()
  if os and os.clock then
    return os.clock()
  end
  if os and os.time then
    return os.time()
  end
  return 0
end

local function build(event_type, data)
  local ev = {}
  if data then
    for k, v in pairs(data) do
      ev[k] = v
    end
  end
  ev.type = event_type
  if ev.event_id == nil then
    ev.event_id = next_id()
  end
  if ev.time == nil then
    ev.time = now()
  end
  return ev
end

M.schemas = {
  TaskStarted = {
    required = { "task_id" },
    types = { task_id = "string", provider_id = "string", event_id = "string", time = "number" },
  },
  TaskFinished = {
    required = { "task_id" },
    types = { task_id = "string", duration = "number", event_id = "string", time = "number" },
  },
  TaskCompleted = {
    required = { "task_id" },
    types = { task_id = "string", result = "table", duration = "number", event_id = "string", time = "number" },
  },
  TaskFailed = {
    required = { "task_id" },
    types = { task_id = "string", error = "any", error_code = "string", reason = "string", event_id = "string", time = "number" },
  },
  StorageMutation = {
    required = { "item", "count" },
    types = { item = "string", count = "number", delta = "number", balance = "number", storage_id = "string", event_id = "string", time = "number" },
  },
  ResourceReserved = {
    required = { "item", "count" },
    types = { item = "string", count = "number", requester_id = "string", event_id = "string", time = "number" },
  },
  ResourceReleased = {
    required = { "item", "count" },
    types = { item = "string", count = "number", requester_id = "string", event_id = "string", time = "number" },
  },
  MachineAllocated = {
    required = { "machine_id" },
    types = { machine_id = "string", recipe = "table", event_id = "string", time = "number" },
  },
  MachineFreed = {
    required = { "machine_id" },
    types = { machine_id = "string", event_id = "string", time = "number" },
  },
  MachineLocked = {
    required = { "machine_id", "machine_type" },
    types = { machine_id = "string", machine_type = "string", event_id = "string", time = "number" },
  },
  MachineUnlocked = {
    required = { "machine_id", "machine_type" },
    types = { machine_id = "string", machine_type = "string", event_id = "string", time = "number" },
  },
  MachineDetected = {
    required = { "machine_id", "machine_type", "provider" },
    types = { machine_id = "string", machine_type = "string", provider = "table", event_id = "string", time = "number" },
  },
  MachineRemoved = {
    required = { "machine_id" },
    types = { machine_id = "string", event_id = "string", time = "number" },
  },
  MachineDisabled = {
    required = { "machine_id" },
    types = { machine_id = "string", event_id = "string", time = "number" },
  },
  MachineEnabled = {
    required = { "machine_id" },
    types = { machine_id = "string", event_id = "string", time = "number" },
  },
  StorageDetected = {
    required = { "provider" },
    types = { provider = "table", storage_id = "string", event_id = "string", time = "number" },
  },
  StorageRemoved = {
    required = {},
    types = { storage_id = "string", event_id = "string", time = "number" },
  },
  StorageDisabled = {
    required = {},
    types = { storage_id = "string", event_id = "string", time = "number" },
  },
  StorageEnabled = {
    required = {},
    types = { storage_id = "string", event_id = "string", time = "number" },
  },
  Tick = {
    required = { "now" },
    types = { now = "number", event_id = "string", time = "number" },
  },
  BatchSplit = {
    required = { "storage_id", "original_size", "batches_count" },
    types = { storage_id = "string", original_size = "table", batches_count = "number", event_id = "string", time = "number" },
  },
  BatchQueued = {
    required = { "storage_id", "batch_id" },
    types = { storage_id = "string", batch_id = "string", event_id = "string", time = "number" },
  },
  SupplyRequested = {
    required = { "batch_id" },
    types = { batch_id = "string", event_id = "string", time = "number" },
  },
  BatchFailed = {
    required = { "storage_id", "batch_id" },
    types = { storage_id = "string", batch_id = "string", event_id = "string", time = "number" },
  },
  BatchDone = {
    required = { "storage_id", "batch_id" },
    types = { storage_id = "string", batch_id = "string", event_id = "string", time = "number" },
  },
  SupplySatisfied = {
    required = { "batch_id" },
    types = { batch_id = "string", event_id = "string", time = "number" },
  },
}

function M.TaskStarted(fields) return build("TaskStarted", fields) end
function M.TaskFinished(fields) return build("TaskFinished", fields) end
function M.TaskCompleted(fields) return build("TaskCompleted", fields) end
function M.TaskFailed(fields) return build("TaskFailed", fields) end
function M.StorageMutation(fields) return build("StorageMutation", fields) end
function M.ResourceReserved(fields) return build("ResourceReserved", fields) end
function M.ResourceReleased(fields) return build("ResourceReleased", fields) end
function M.MachineAllocated(fields) return build("MachineAllocated", fields) end
function M.MachineFreed(fields) return build("MachineFreed", fields) end
function M.MachineLocked(fields) return build("MachineLocked", fields) end
function M.MachineUnlocked(fields) return build("MachineUnlocked", fields) end
function M.MachineDetected(fields) return build("MachineDetected", fields) end
function M.MachineRemoved(fields) return build("MachineRemoved", fields) end
function M.MachineDisabled(fields) return build("MachineDisabled", fields) end
function M.MachineEnabled(fields) return build("MachineEnabled", fields) end
function M.StorageDetected(fields) return build("StorageDetected", fields) end
function M.StorageRemoved(fields) return build("StorageRemoved", fields) end
function M.StorageDisabled(fields) return build("StorageDisabled", fields) end
function M.StorageEnabled(fields) return build("StorageEnabled", fields) end
function M.Tick(fields) return build("Tick", fields) end
function M.BatchSplit(fields) return build("BatchSplit", fields) end
function M.BatchQueued(fields) return build("BatchQueued", fields) end
function M.SupplyRequested(fields) return build("SupplyRequested", fields) end
function M.BatchFailed(fields) return build("BatchFailed", fields) end
function M.BatchDone(fields) return build("BatchDone", fields) end
function M.SupplySatisfied(fields) return build("SupplySatisfied", fields) end

return M
