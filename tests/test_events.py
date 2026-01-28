import unittest

from events import EventBus, MachineDetected, MachineDisabled, MachineEnabled, MachineRemoved
from machine_manager import MachineManager
from machines import MachineCatalog
from providers.machine.base import MachineProvider, TaskHandle, TaskState
from models import Recipe, ItemStack


class DummyMachine(MachineProvider):
    def can_craft(self, recipe: Recipe, machine) -> bool:
        return True

    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        return TaskHandle(id="d", state=TaskState.DONE, outputs={})

    def poll(self, handle: TaskHandle) -> TaskState:
        return handle.state

    def collect_outputs(self, handle: TaskHandle):
        return {}

    def configure(self, machine, **params):
        return True


class EventBusTest(unittest.TestCase):
    def test_machine_events_update_manager(self) -> None:
        bus = EventBus()
        catalog = MachineCatalog()
        manager = MachineManager(catalog)
        manager.subscribe(bus)

        provider = DummyMachine()
        bus.emit(MachineDetected(machine_type="t", machine_id="m1", provider=provider))
        self.assertTrue(manager.dirty)
        allocator = manager.build_allocator()
        self.assertFalse(manager.dirty)
        self.assertTrue(allocator.supports("t"))

        bus.emit(MachineDisabled(machine_id="m1"))
        self.assertTrue(manager.dirty)
        allocator = manager.build_allocator()
        self.assertFalse(allocator.supports("t"))

        bus.emit(MachineEnabled(machine_id="m1"))
        allocator = manager.build_allocator()
        self.assertTrue(allocator.supports("t"))

        bus.emit(MachineRemoved(machine_id="m1"))
        allocator = manager.build_allocator()
        self.assertFalse(allocator.supports("t"))

    def test_eventbus_filters_by_type(self) -> None:
        bus = EventBus()
        called = {"detected": 0}

        def on_detected(event: MachineDetected) -> None:
            called["detected"] += 1

        bus.subscribe(MachineDetected, on_detected)
        bus.emit(MachineDisabled(machine_id="m1"))
        self.assertEqual(called["detected"], 0)
        bus.emit(MachineDetected(machine_type="t", machine_id="m1", provider=DummyMachine()))
        self.assertEqual(called["detected"], 1)


if __name__ == "__main__":
    unittest.main()
