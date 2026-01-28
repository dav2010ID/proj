from __future__ import annotations

from typing import Dict, Iterable, List, Mapping, Tuple

from providers.resource.base import ResourceProvider
from util.itemkey import normalize
from util.log import debug


class MemoryResourceProvider(ResourceProvider):
    def __init__(self, available: Dict[str, int] | None = None) -> None:
        self._available: Dict[str, int] = dict(available or {})
        self._consumed: List[Tuple[str, int]] = []
        self._added: List[Tuple[str, int]] = []
        self._frozen = False
        self._allowed: set[str] | None = None

    def prepare(self, reachable_items: Iterable[str]) -> None:
        self._allowed = {normalize(item) for item in reachable_items}

    def get(self, item_key: str) -> int:
        key = normalize(item_key)
        if self._allowed is not None and key not in self._allowed:
            raise RuntimeError("get outside reachable items")
        if self._frozen and key not in self._available:
            raise RuntimeError("get after snapshot")
        if key not in self._available:
            self._available[key] = 0
        value = int(self._available.get(key, 0))
        debug(f"resource.get item={key} value={value}")
        return value

    def consume(self, item_key: str, count: int) -> None:
        key = normalize(item_key)
        current = self._available.get(key, 0)
        if count < 0:
            raise ValueError("count must be non-negative")
        if current < count:
            raise ValueError("insufficient stock")
        self._available[key] = current - count
        if count:
            self._consumed.append((key, count))
        debug(f"resource.consume item={key} count={count} left={self._available[key]}")

    def commit(self) -> None:
        self._consumed.clear()
        self._added.clear()
        debug("resource.commit")

    def rollback(self) -> None:
        for key, count in reversed(self._added):
            self._available[key] = self._available.get(key, 0) - count
        for key, count in reversed(self._consumed):
            self._available[key] = self._available.get(key, 0) + count
        self._consumed.clear()
        self._added.clear()
        debug("resource.rollback")

    def snapshot(self) -> Mapping[str, int]:
        if self._frozen:
            raise RuntimeError("snapshot already taken")
        self._frozen = True
        return dict(self._available)

    def add(self, item_key: str, count: int) -> None:
        key = normalize(item_key)
        if count < 0:
            raise ValueError("count must be non-negative")
        self._available[key] = self._available.get(key, 0) + count
        if count:
            self._added.append((key, count))
        debug(f"resource.add item={key} count={count} total={self._available[key]}")
