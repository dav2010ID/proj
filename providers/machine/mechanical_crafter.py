from __future__ import annotations

from machines import MachineInstance
from providers.machine.base import MachineProvider, TaskHandle, TaskState
from models import Recipe


class MechanicalCrafterProvider(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        return recipe.machine == "mechanical_crafter"

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        return TaskHandle(
            id=f"mechanical_crafter:{recipe.id}",
            state=TaskState.FAILED,
            error="mechanical_crafter_not_implemented",
        )

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle) -> dict[str, int]:
        return {}

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        return False
