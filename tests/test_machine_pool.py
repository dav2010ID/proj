import unittest

from machines import MachineAllocator, MachineInstance, MachineState
from providers.machine.base import MachineProvider, TaskHandle, TaskState
from models import Recipe, ItemStack


class DummyMachine(MachineProvider):
    def can_craft(self, recipe: Recipe, machine: MachineInstance) -> bool:
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        return TaskHandle(id="d", state=TaskState.DONE, outputs={})

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle):
        return {}

    def configure(self, machine: MachineInstance, **params: int | str) -> bool:
        return False


class MachineAllocatorTest(unittest.TestCase):
    def test_acquire_unlock(self) -> None:
        machine = MachineInstance(id="m1", type="t", provider=DummyMachine())
        pool = MachineAllocator([machine])
        acquired = pool.lock("t")
        self.assertIsNotNone(acquired)
        self.assertEqual(acquired.id, "m1")
        with self.assertRaises(RuntimeError):
            pool.unlock("unknown")
        pool.unlock("m1")

    def test_supports(self) -> None:
        machine = MachineInstance(id="m1", type="t", provider=DummyMachine())
        pool = MachineAllocator([machine])
        self.assertTrue(pool.supports("t"))
        self.assertFalse(pool.supports("x"))

    def test_find_compatible(self) -> None:
        machine = MachineInstance(id="m1", type="t", provider=DummyMachine(), state=MachineState())
        pool = MachineAllocator([machine])
        recipe = Recipe(
            id="r",
            inputs=[ItemStack(item="item:a", count=1)],
            outputs=[ItemStack(item="item:b", count=1)],
            machine="t",
        )
        acquired = pool.find_compatible(recipe)
        self.assertIsNotNone(acquired)
        self.assertEqual(acquired.id, "m1")


if __name__ == "__main__":
    unittest.main()
