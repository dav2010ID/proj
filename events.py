from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Protocol, Type


class Event:
    pass


class EventSource(Protocol):
    def poll(self) -> list[Event]:
        ...


class EventBus:
    def __init__(self) -> None:
        self._subscribers: Dict[Type[Event], List[Callable[[Event], None]]] = {}

    def subscribe(self, event_type: Type[Event], handler: Callable[[Event], None]) -> None:
        self._subscribers.setdefault(event_type, []).append(handler)

    def emit(self, event: Event) -> None:
        for handler in self._subscribers.get(type(event), []):
            handler(event)


@dataclass(frozen=True)
class MachineDetected(Event):
    machine_type: str
    machine_id: str
    provider: object


@dataclass(frozen=True)
class MachineRemoved(Event):
    machine_id: str


@dataclass(frozen=True)
class MachineDisabled(Event):
    machine_id: str


@dataclass(frozen=True)
class MachineEnabled(Event):
    machine_id: str


@dataclass(frozen=True)
class RecipeAdded(Event):
    recipe_id: str


@dataclass(frozen=True)
class RecipeRemoved(Event):
    recipe_id: str
