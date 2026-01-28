from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from providers.machine.base import MachineProvider


@dataclass
class MachineState:
    circuit: int | None = None
    mode: str | None = None


@dataclass(frozen=True)
class MachineInstance:
    id: str
    type: str
    provider: MachineProvider
    state: MachineState = field(default_factory=MachineState)


class MachineAllocator:
    def __init__(self, machines: List[MachineInstance]) -> None:
        self._free: Dict[str, MachineInstance] = {m.id: m for m in machines}
        self._busy: Dict[str, MachineInstance] = {}

    def lock(self, machine_type: str) -> Optional[MachineInstance]:
        for machine_id, machine in list(self._free.items()):
            if machine.type == machine_type:
                assert machine_id not in self._busy
                self._free.pop(machine_id)
                self._busy[machine_id] = machine
                return machine
        return None

    def find_compatible(self, recipe) -> Optional[MachineInstance]:
        for machine_id, machine in list(self._free.items()):
            if machine.type != recipe.machine:
                continue
            if not machine.provider.can_craft(recipe, machine):
                continue
            assert machine_id not in self._busy
            self._free.pop(machine_id)
            self._busy[machine_id] = machine
            return machine
        return None

    def unlock(self, machine_id: str) -> None:
        if machine_id not in self._busy:
            raise RuntimeError("release_non_busy")
        machine = self._busy.pop(machine_id)
        self._free[machine.id] = machine

    def supports(self, machine_type: str) -> bool:
        for machine in self._free.values():
            if machine.type == machine_type:
                return True
        for machine in self._busy.values():
            if machine.type == machine_type:
                return True
        return False

    def supports_recipe(self, recipe) -> bool:
        for machine in self._free.values():
            if machine.type != recipe.machine:
                continue
            if machine.provider.can_craft(recipe, machine):
                return True
        for machine in self._busy.values():
            if machine.type != recipe.machine:
                continue
            if machine.provider.can_craft(recipe, machine):
                return True
        return False


class MachineCatalog:
    def __init__(self) -> None:
        self._instances: Dict[str, MachineInstance] = {}

    def register(self, machine_type: str, provider: MachineProvider, machine_id: str) -> None:
        self._instances[machine_id] = MachineInstance(id=machine_id, type=machine_type, provider=provider)

    def unregister(self, machine_id: str) -> None:
        self._instances.pop(machine_id, None)

    def list_instances(self) -> List[MachineInstance]:
        return list(self._instances.values())

    def build_allocator(self) -> MachineAllocator:
        return MachineAllocator(self.list_instances())
