# Architecture Rules

This document defines the architectural rules and invariants of the system.
Breaking these rules is considered a design error.

---

## 1. Layer Model

The system is strictly layered.

Layers (from bottom to top):

1. Core
2. Runtime
3. Providers
4. Entry points

Dependency direction is one-way.

Core ← Runtime ← Providers
^
(via entry points only)


No layer may depend on a layer above it.

---

## 2. Core Layer

Files:
- core.recipe
- core.steps
- core.planner
- core.util
- core.error_codes
- core.log

Rules:

- Core MUST NOT import runtime.
- Core MUST NOT import providers.
- Core MUST contain no async logic.
- Core MUST be deterministic.

Planner rules:

- Planner reasons only about logical needs.
- Planner knows nothing about latency.
- Planner knows nothing about machines or storage internals.
- Planner produces an abstract plan only.

Core utilities:

- core.util must remain dependency-free.
- core.log must not grow behavior.

---

## 3. Runtime Layer

Files:
- executor
- supply_router
- multi_storage
- task_state
- virtual_world
- virtual_storage
- virtual_async_storage
- virtual_machine
- virtual_scheduler
- machine_manager
- event_bus

Rules:

- Runtime MUST NOT import planner internals.
- Runtime MUST NOT modify recipe graphs.
- Runtime coordinates execution only.

Executor rules:

- Executor does not access storage directly.
- Executor uses supply routing.
- Executor enforces execution order.
- Executor owns commit and rollback.
- Executor must yield periodically.

Supply routing rules:

- Routing is isolated from execution.
- Routing enforces batch limits.
- Routing groups supply per storage.

Async storage rules:

- No resource is available before DONE.
- collect is allowed only after DONE.
- FAILED requests mutate nothing.
- Batch is atomic per storage.

---

## 4. Providers Layer

Files:
- providers.machine.*
- providers.resource.*

Rules:

- Providers MUST NOT import executor.
- Providers MUST NOT import planner.
- Providers MUST NOT coordinate with each other.
- Providers implement contracts only.

Machine providers:

- One machine handles one task at a time.
- Outputs are emitted once.
- Provider does not manage scheduling.

Resource providers:

- ResourceProvider controls mutation.
- Snapshot freezes mutation.
- Async providers respect batch contracts.

Every provider MUST have a contract test.

---

## 5. virtual_world

virtual_world is an orchestration root.

Rules:

- virtual_world wires components.
- virtual_world contains no planning logic.
- virtual_world contains no execution policy.
- Business logic must live in submodules.

virtual_world is allowed to depend on:
- scheduler
- storage
- machine manager
- event bus

Nothing may depend on virtual_world.

---

## 6. Entry Points

Files:
- main.lua
- startup.lua

Rules:

- Entry points may import all layers.
- Entry points perform wiring only.
- Entry points contain no logic.

No other file may import entry points.

---

## 7. Error Handling

- Error codes are defined centrally.
- Runtime errors use structured error objects.
- Providers must use error codes.
- Planner errors are deterministic.

---

## 8. Determinism Rules

- Planner output must be deterministic.
- Supply routing must be deterministic.
- Batch splitting must be deterministic.
- Test execution order must be stable.

---

## 9. Test Rules

- No test depends on another test.
- Contract tests are mandatory for providers.
- Async behavior must be tested with virtual scheduler.
- Snapshot and rollback must be tested.

---

## 10. Invariants Summary

These must never be violated:

- Core does not depend on runtime.
- Planner does not know execution details.
- Executor does not know storage internals.
- Providers do not coordinate.
- Async supply blocks craft.
- Batch is atomic.
- Rollback leaves no residue.

If any invariant breaks, architecture must be reviewed.

---