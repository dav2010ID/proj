local M = {}

local function ensure_state(plan_graph, state)
  state = state or {}
  state.graph = plan_graph
  state.done = state.done or {}
  state.started = state.started or {}
  state.pending = state.pending or {}
  state.policy = state.policy
  if not state.initialized then
    for id = 1, #plan_graph.nodes do
      state.pending[id] = true
    end
    state.initialized = true
  end
  return state
end

function M.schedule(plan_graph, state, policy)
  state = state or {}
  state.policy = policy
  return ensure_state(plan_graph, state)
end

function M.get_ready_tasks(state)
  local ready = {}
  for id, _ in pairs(state.pending or {}) do
    if not state.started[id] then
      local node = state.graph.nodes[id]
      local ok = true
      if node and node.inputs then
        for item, required in pairs(node.inputs) do
          local available = (state.available and state.available[item]) or 0
          if available < required then
            ok = false
            break
          end
        end
      end
      if ok then
        table.insert(ready, { id = id, node = node })
      end
    end
  end
  table.sort(ready, function(a, b)
    return a.id < b.id
  end)
  if state.policy and state.policy.ready_limit then
    local limit = state.policy:ready_limit()
    if limit and #ready > limit then
      local limited = {}
      for i = 1, limit do
        limited[i] = ready[i]
      end
      return limited
    end
  end
  return ready
end

function M.mark_started(state, task)
  state.started[task.id] = true
end

function M.update_after_completion(task, state)
  state.done[task.id] = true
  state.pending[task.id] = nil
end

function M.all_done(state)
  return next(state.pending) == nil
end

return M
