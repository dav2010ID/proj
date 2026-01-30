local M = {}

local function ensure_state(plan_graph, state)
  state = state or {}
  state.graph = plan_graph
  state.done = state.done or {}
  state.started = state.started or {}
  state.pending = state.pending or {}
  if not state.initialized then
    for id = 1, #plan_graph.nodes do
      state.pending[id] = true
    end
    state.initialized = true
  end
  return state
end

function M.schedule(plan_graph, state)
  return ensure_state(plan_graph, state)
end

function M.get_ready_tasks(state)
  local ready = {}
  for id, _ in pairs(state.pending or {}) do
    if not state.started[id] then
      local deps = state.graph:get_dependencies(id)
      local ok = true
      for _, dep in ipairs(deps) do
        if not state.done[dep] then
          ok = false
          break
        end
      end
      if ok then
        table.insert(ready, { id = id, node = state.graph.nodes[id] })
      end
    end
  end
  table.sort(ready, function(a, b)
    return a.id < b.id
  end)
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
