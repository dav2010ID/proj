from __future__ import annotations

from dataclasses import dataclass, field
from typing import Set

from events import EventBus, MachineDetected, MachineDisabled, MachineEnabled, MachineRemoved
from machines import MachineAllocator, MachineCatalog, MachineInstance
from providers.machine.base import MachineProvider


@dataclass
class MachineManager:
    catalog: MachineCatalog
    dirty: bool = False
    _disabled: Set[str] = field(default_factory=set)

    def subscribe(self, bus: EventBus) -> None:
        bus.subscribe(MachineDetected, self.on_machine_detected)
        bus.subscribe(MachineRemoved, self.on_machine_removed)
        bus.subscribe(MachineDisabled, self.on_machine_disabled)
        bus.subscribe(MachineEnabled, self.on_machine_enabled)

    def on_machine_detected(self, event: MachineDetected) -> None:
        if not isinstance(event.provider, MachineProvider):
            raise TypeError("provider must be MachineProvider")
        self.catalog.register(event.machine_type, event.provider, event.machine_id)
        self._disabled.discard(event.machine_id)
        self.dirty = True

    def on_machine_removed(self, event: MachineRemoved) -> None:
        self.catalog.unregister(event.machine_id)
        self._disabled.discard(event.machine_id)
        self.dirty = True

    def on_machine_disabled(self, event: MachineDisabled) -> None:
        self._disabled.add(event.machine_id)
        self.dirty = True

    def on_machine_enabled(self, event: MachineEnabled) -> None:
        self._disabled.discard(event.machine_id)
        self.dirty = True

    def build_allocator(self) -> MachineAllocator:
        active = [m for m in self.catalog.list_instances() if m.id not in self._disabled]
        self.dirty = False
        return MachineAllocator(active)
