from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Protocol, Union

from util.itemkey import normalize


class ExecutionContext(Protocol):
    def execute_supply(self, step: "SupplyStep") -> bool:
        ...

    def execute_craft(self, step: "CraftStep") -> bool:
        ...


@dataclass(frozen=True)
class ItemStack:
    item: str
    count: int

    def __post_init__(self) -> None:
        if self.count <= 0:
            raise ValueError("ItemStack.count must be > 0")
        object.__setattr__(self, "item", normalize(self.item))


@dataclass(frozen=True)
class Recipe:
    id: str
    inputs: List[ItemStack]
    outputs: List[ItemStack]
    machine: str
    conditions: "RecipeConditions | None" = None
    priority: int = 0

    def __post_init__(self) -> None:
        if not self.outputs:
            raise ValueError("Recipe.outputs must not be empty")


@dataclass(frozen=True)
class RecipeConditions:
    requires: Dict[str, int | str]


@dataclass(frozen=True)
class SupplyStep:
    item: str
    count: int

    def __post_init__(self) -> None:
        if self.count <= 0:
            raise ValueError("SupplyStep.count must be > 0")
        object.__setattr__(self, "item", normalize(self.item))

    def execute(self, ctx: ExecutionContext) -> bool:
        return ctx.execute_supply(self)


@dataclass(frozen=True)
class CraftStep:
    recipe: Recipe
    times: int

    def __post_init__(self) -> None:
        if self.times <= 0:
            raise ValueError("CraftStep.times must be > 0")

    def execute(self, ctx: ExecutionContext) -> bool:
        return ctx.execute_craft(self)


PlanStep = Union[SupplyStep, CraftStep]
