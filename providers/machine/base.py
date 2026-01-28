from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Dict, TYPE_CHECKING

from models import Recipe

if TYPE_CHECKING:
    from machines import MachineInstance

class TaskState(Enum):
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"


@dataclass
class TaskHandle:
    id: str
    state: TaskState
    outputs: Dict[str, int] | None = None
    error: str | None = None


class MachineProvider(ABC):
    @abstractmethod
    def can_craft(self, recipe: Recipe, machine: "MachineInstance") -> bool:
        raise NotImplementedError

    @abstractmethod
    def start(self, recipe: Recipe, times: int) -> TaskHandle:
        raise NotImplementedError

    @abstractmethod
    def poll(self, handle: TaskHandle) -> TaskState:
        raise NotImplementedError

    @abstractmethod
    def collect_outputs(self, handle: TaskHandle) -> Dict[str, int]:
        raise NotImplementedError

    @abstractmethod
    def configure(self, machine: "MachineInstance", **params: int | str) -> bool:
        raise NotImplementedError
