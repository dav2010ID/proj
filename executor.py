from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Deque, Dict, List, Tuple

from machines import MachineAllocator
from models import CraftStep, PlanStep, SupplyStep
from providers.machine.base import TaskHandle, TaskState
from providers.resource.base import ResourceProvider
from util.log import debug


class ExecutionError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass
class Task:
    step: CraftStep
    machine_id: str
    provider: object
    handle: TaskHandle


class ExecutionContext:
    def __init__(self, resource_provider: ResourceProvider, machine_allocator: MachineAllocator) -> None:
        self.resource = resource_provider
        self.machine_allocator = machine_allocator
        self.buffer: Dict[str, int] = {}
        self.inflight: List[Task] = []

    def execute_supply(self, step: SupplyStep) -> bool:
        debug(f"execute supply item={step.item} count={step.count}")
        self.resource.consume(step.item, step.count)
        self.buffer[step.item] = self.buffer.get(step.item, 0) + step.count
        return True

    def execute_craft(self, step: CraftStep) -> bool:
        if not _inputs_available(step, self.buffer):
            return False
        machine = self.machine_allocator.find_compatible(step.recipe)
        if not machine:
            return False
        _consume_inputs(step, self.buffer)
        handle = machine.provider.start(step.recipe, step.times)
        self.inflight.append(Task(step=step, machine_id=machine.id, provider=machine.provider, handle=handle))
        return True

    def poll_tasks(self) -> bool:
        progressed = False
        for task in list(self.inflight):
            state = task.provider.poll(task.handle)
            if state == TaskState.RUNNING:
                continue
            if state == TaskState.FAILED:
                self.machine_allocator.unlock(task.machine_id)
                raise ExecutionError(task.handle.error or "craft_failed")
            outputs = task.provider.collect_outputs(task.handle)
            for item, count in outputs.items():
                self.buffer[item] = self.buffer.get(item, 0) + count
                self.resource.add(item, count)
            self.machine_allocator.unlock(task.machine_id)
            self.inflight.remove(task)
            progressed = True
        return progressed


def execute(plan: List[PlanStep], resource_provider: ResourceProvider, machine_allocator: MachineAllocator) -> Tuple[bool, str | None]:
    ctx = ExecutionContext(resource_provider, machine_allocator)
    ready: Deque[PlanStep] = deque(plan)

    try:
        debug(f"execute preflight steps={len(plan)}")
        for step in plan:
            if isinstance(step, CraftStep):
                if not machine_allocator.supports_recipe(step.recipe):
                    raise ExecutionError("no_compatible_machine")

        while ready or ctx.inflight:
            progressed = False

            for _ in range(len(ready)):
                step = ready.popleft()
                progressed_step = step.execute(ctx)
                if not progressed_step:
                    ready.append(step)
                else:
                    progressed = True

            progressed = ctx.poll_tasks() or progressed

            if not progressed:
                raise ExecutionError("deadlock")
    except ExecutionError as exc:
        resource_provider.rollback()
        return False, exc.code
    except Exception as exc:  # prototype: catch for rollback
        resource_provider.rollback()
        return False, str(exc)

    resource_provider.commit()
    return True, None


def _inputs_available(step: CraftStep, buffer: Dict[str, int]) -> bool:
    for input_item in step.recipe.inputs:
        need = input_item.count * step.times
        if buffer.get(input_item.item, 0) < need:
            return False
    return True


def _consume_inputs(step: CraftStep, buffer: Dict[str, int]) -> None:
    for input_item in step.recipe.inputs:
        item = input_item.item
        need = input_item.count * step.times
        buffer[item] = buffer.get(item, 0) - need
