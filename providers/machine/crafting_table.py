from __future__ import annotations

from machines import MachineInstance
from providers.machine.base import MachineProvider, TaskHandle, TaskState
from models import Recipe
from util.log import info


class CraftingTableProvider(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        if recipe.machine != "crafting_table":
            return False
        if recipe.conditions and recipe.conditions.requires:
            return False
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        for _ in range(times):
            info(f"Crafting {recipe.id} on crafting_table")
        outputs = {out.item: out.count * times for out in recipe.outputs}
        return TaskHandle(id=f"crafting_table:{recipe.id}", state=TaskState.DONE, outputs=outputs)

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle) -> dict[str, int]:
        return dict(handle.outputs or {})

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        return not params
