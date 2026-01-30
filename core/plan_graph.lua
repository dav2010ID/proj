local M = {}

local PlanGraph = {}
PlanGraph.__index = PlanGraph

function M.new()
  return setmetatable({
    nodes = {},
    edges = {},
    deps = {},
    flows = {},
  }, PlanGraph)
end

function PlanGraph:add_node(node)
  assert(node, "node required")
  local id = #self.nodes + 1
  self.nodes[id] = node
  self.edges[id] = self.edges[id] or {}
  self.deps[id] = self.deps[id] or {}
  return id
end

function PlanGraph:add_edge(from_id, to_id)
  assert(self.nodes[from_id], "invalid from_id")
  assert(self.nodes[to_id], "invalid to_id")
  if not self.edges[from_id][to_id] then
    self.edges[from_id][to_id] = true
    self.deps[to_id][from_id] = true
  end
end

function PlanGraph:add_flow(from_id, to_id, item, amount)
  assert(self.nodes[from_id], "invalid from_id")
  assert(self.nodes[to_id], "invalid to_id")
  if not self.edges[from_id][to_id] then
    self.edges[from_id][to_id] = true
    self.deps[to_id][from_id] = true
  end
  self.flows[to_id] = self.flows[to_id] or {}
  table.insert(self.flows[to_id], { from = from_id, item = item, amount = amount })
end

function PlanGraph:get_dependencies(node_id)
  local list = {}
  local dep_map = self.deps[node_id] or {}
  for id, _ in pairs(dep_map) do
    table.insert(list, id)
  end
  table.sort(list)
  return list
end

function PlanGraph:topological_sort()
  local indegree = {}
  local remaining = {}
  for id = 1, #self.nodes do
    indegree[id] = 0
    remaining[id] = true
  end
  for _, tos in pairs(self.edges) do
    for to, _ in pairs(tos) do
      indegree[to] = indegree[to] + 1
    end
  end

  local order = {}
  while true do
    local next_id = nil
    for id = 1, #self.nodes do
      if remaining[id] and indegree[id] == 0 then
        next_id = id
        break
      end
    end
    if not next_id then
      break
    end
    remaining[next_id] = nil
    table.insert(order, next_id)
    for to, _ in pairs(self.edges[next_id] or {}) do
      indegree[to] = indegree[to] - 1
    end
  end

  if #order ~= #self.nodes then
    error("plan_graph_cycle")
  end

  return order
end

function M.from_steps(steps)
  local graph = M.new()
  local last_producer = {}
  for _, step in ipairs(steps or {}) do
    local node
    if step.kind == "supply" then
      node = {
        kind = "supply",
        item = step.item,
        count = step.count,
      }
    elseif step.kind == "craft" then
      node = {
        kind = "craft",
        recipe = step.recipe,
        times = step.times,
      }
    else
      error("unknown_step")
    end
    local id = graph:add_node(node)
    if node.kind == "craft" then
      for _, input in ipairs(node.recipe.inputs or {}) do
        local dep = last_producer[input.item]
        if dep then
          graph:add_edge(dep, id)
        end
      end
      for _, output in ipairs(node.recipe.outputs or {}) do
        last_producer[output.item] = id
      end
    else
      last_producer[node.item] = id
    end
  end
  return graph
end

function M.normalize(graph)
  if not graph or type(graph.nodes) ~= "table" then
    error("invalid_graph")
  end
  local out = M.new()
  local key_to_id = {}
  local old_to_new = {}

  local function merge_map(dst, src)
    if not src then
      return
    end
    for k, v in pairs(src) do
      dst[k] = (dst[k] or 0) + v
    end
  end

  local function node_key(node, id)
    if node.kind == "supply" then
      return "supply:" .. tostring(node.item or "")
    elseif node.kind == "craft" then
      local rid = node.recipe and node.recipe.id or tostring(node.recipe or "")
      local machine = node.recipe and node.recipe.machine or ""
      return "craft:" .. tostring(rid) .. ":" .. tostring(machine)
    end
    return "node:" .. tostring(id)
  end

  for id = 1, #graph.nodes do
    local node = graph.nodes[id]
    local key = node_key(node, id)
    local new_id = key_to_id[key]
    if not new_id then
      local new_node
      if node.kind == "supply" then
        local count = node.count or 0
        new_node = {
          kind = "supply",
          item = node.item,
          count = count,
          inputs = {},
          outputs = { [node.item] = count },
        }
      elseif node.kind == "craft" then
        new_node = {
          kind = "craft",
          recipe = node.recipe,
          times = node.times or 0,
          inputs = {},
          outputs = {},
        }
        merge_map(new_node.inputs, node.inputs)
        merge_map(new_node.outputs, node.outputs)
      else
        new_node = node
      end
      new_id = out:add_node(new_node)
      key_to_id[key] = new_id
    else
      local target = out.nodes[new_id]
      if node.kind == "supply" then
        local count = node.count or 0
        target.count = (target.count or 0) + count
        target.outputs = target.outputs or {}
        target.outputs[node.item] = (target.outputs[node.item] or 0) + count
      elseif node.kind == "craft" then
        target.times = (target.times or 0) + (node.times or 0)
        target.inputs = target.inputs or {}
        target.outputs = target.outputs or {}
        merge_map(target.inputs, node.inputs)
        merge_map(target.outputs, node.outputs)
      end
    end
    old_to_new[id] = new_id
  end

  for from_id, tos in pairs(graph.edges or {}) do
    local new_from = old_to_new[from_id]
    if new_from then
      for to_id, _ in pairs(tos) do
        local new_to = old_to_new[to_id]
        if new_to and new_to ~= new_from then
          out:add_edge(new_from, new_to)
        end
      end
    end
  end

  local merged_flows = {}
  for to_id, flows in pairs(graph.flows or {}) do
    local new_to = old_to_new[to_id]
    if new_to then
      merged_flows[new_to] = merged_flows[new_to] or {}
      for _, flow in ipairs(flows) do
        local new_from = old_to_new[flow.from]
        if new_from and new_from ~= new_to then
          local item = flow.item
          local key = tostring(new_from) .. "|" .. tostring(item or "")
          merged_flows[new_to][key] = merged_flows[new_to][key] or { from = new_from, item = item, amount = 0 }
          merged_flows[new_to][key].amount = merged_flows[new_to][key].amount + (flow.amount or 0)
        end
      end
    end
  end
  for new_to, map in pairs(merged_flows) do
    for _, flow in pairs(map) do
      out:add_flow(flow.from, new_to, flow.item, flow.amount)
    end
  end

  return out
end

return M
