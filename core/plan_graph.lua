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

return M
