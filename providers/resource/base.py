from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Iterable, Mapping


class ResourceProvider(ABC):
    def prepare(self, reachable_items: Iterable[str]) -> None:
        return None

    @abstractmethod
    def get(self, item_key: str) -> int:
        raise NotImplementedError

    @abstractmethod
    def consume(self, item_key: str, count: int) -> None:
        raise NotImplementedError

    @abstractmethod
    def commit(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def rollback(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def snapshot(self) -> Mapping[str, int]:
        raise NotImplementedError

    @abstractmethod
    def add(self, item_key: str, count: int) -> None:
        raise NotImplementedError
