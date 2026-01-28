from __future__ import annotations

import unittest

from executor import execute
from machines import MachineAllocator, MachineInstance, MachineState
from models import CraftStep, ItemStack, Recipe, RecipeConditions, SupplyStep
from providers.machine.base import MachineProvider, TaskHandle, TaskState
from providers.resource.memory import MemoryResourceProvider


class FailingMachine(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        return TaskHandle(id="fail", state=TaskState.FAILED, error="craft_failed")

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle):
        return {}

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        return False


class OkMachine(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        outputs = {out.item: out.count * times for out in recipe.outputs}
        return TaskHandle(id="ok", state=TaskState.DONE, outputs=outputs)

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle):
        return dict(handle.outputs or {})

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        return False


class ConditionedMachine(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        if recipe.machine != machine.type:
            return False
        if not recipe.conditions:
            return True
        for key, value in recipe.conditions.requires.items():
            if getattr(machine.state, key, None) != value:
                return False
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        outputs = {out.item: out.count * times for out in recipe.outputs}
        return TaskHandle(id="ok", state=TaskState.DONE, outputs=outputs)

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle):
        return dict(handle.outputs or {})

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        for key, value in params.items():
            setattr(machine.state, key, value)
        return True


class ExecutorTest(unittest.TestCase):
    def test_rollback_on_craft_failure(self) -> None:
        resources = MemoryResourceProvider({"item:a": 2})
        plan = [
            SupplyStep(item="item:a", count=1),
            CraftStep(
                recipe=Recipe(
                    id="r",
                    inputs=[ItemStack(item="item:a", count=1)],
                    outputs=[ItemStack(item="item:b", count=1)],
                    machine="m",
                ),
                times=1,
            ),
        ]
        pool = MachineAllocator([MachineInstance(id="m1", type="m", provider=FailingMachine())])
        ok, err = execute(plan, resources, pool)
        self.assertFalse(ok)
        self.assertEqual(err, "craft_failed")
        self.assertEqual(resources.snapshot().get("item:a"), 2)

    def test_preflight_missing_machine(self) -> None:
        resources = MemoryResourceProvider({"item:a": 1})
        plan = [
            CraftStep(
                recipe=Recipe(
                    id="r",
                    inputs=[ItemStack(item="item:a", count=1)],
                    outputs=[ItemStack(item="item:b", count=1)],
                    machine="missing",
                ),
                times=1,
            )
        ]
        pool = MachineAllocator([])
        ok, err = execute(plan, resources, pool)
        self.assertFalse(ok)
        self.assertEqual(err, "no_compatible_machine")
        self.assertEqual(resources.snapshot().get("item:a"), 1)

    def test_success_commit(self) -> None:
        resources = MemoryResourceProvider({"item:a": 1})
        plan = [
            SupplyStep(item="item:a", count=1),
            CraftStep(
                recipe=Recipe(
                    id="r",
                    inputs=[ItemStack(item="item:a", count=1)],
                    outputs=[ItemStack(item="item:b", count=1)],
                    machine="m",
                ),
                times=1,
            ),
        ]
        pool = MachineAllocator([MachineInstance(id="m1", type="m", provider=OkMachine())])
        ok, err = execute(plan, resources, pool)
        self.assertTrue(ok)
        self.assertIsNone(err)
        snapshot = resources.snapshot()
        self.assertEqual(snapshot.get("item:a"), 0)
        self.assertEqual(snapshot.get("item:b"), 1)

    def test_recipe_conditions_no_matching_machine(self) -> None:
        resources = MemoryResourceProvider({"item:a": 1})
        plan = [
            CraftStep(
                recipe=Recipe(
                    id="r",
                    inputs=[ItemStack(item="item:a", count=1)],
                    outputs=[ItemStack(item="item:b", count=1)],
                    machine="gt_machine",
                    conditions=RecipeConditions(requires={"circuit": 4}),
                ),
                times=1,
            )
        ]
        machine = MachineInstance(id="gt1", type="gt_machine", provider=ConditionedMachine(), state=MachineState())
        pool = MachineAllocator([machine])
        ok, err = execute(plan, resources, pool)
        self.assertFalse(ok)
        self.assertEqual(err, "no_compatible_machine")


if __name__ == "__main__":
    unittest.main()
