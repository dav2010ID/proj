from __future__ import annotations

from typing import Iterable

from models import ItemStack, Recipe
from providers.resource.memory import MemoryResourceProvider
from recipes import RecipeRegistry


def registry_from_recipes(recipes: Iterable[Recipe]) -> RecipeRegistry:
    registry = RecipeRegistry()
    for recipe in recipes:
        registry.add(recipe)
    registry.rebuild_index()
    return registry


def recipes_sticks_from_planks() -> list[Recipe]:
    return [
        Recipe(
            id="sticks",
            inputs=[ItemStack(item="item:planks", count=2)],
            outputs=[ItemStack(item="item:sticks", count=4)],
            machine="crafting_table",
            priority=1,
        ),
    ]


def recipes_gear_alternatives() -> list[Recipe]:
    return [
        Recipe(
            id="gear_gold",
            inputs=[ItemStack(item="item:gold", count=1)],
            outputs=[ItemStack(item="item:gear", count=1)],
            machine="crafting_table",
            priority=10,
        ),
        Recipe(
            id="gear_iron",
            inputs=[ItemStack(item="item:iron", count=1)],
            outputs=[ItemStack(item="item:gear", count=1)],
            machine="crafting_table",
            priority=1,
        ),
    ]


def recipes_wash_meal() -> list[Recipe]:
    return [
        Recipe(
            id="wash",
            inputs=[
                ItemStack(item="item:dirty_cloth", count=1),
                ItemStack(item="item:water_bucket", count=1),
            ],
            outputs=[
                ItemStack(item="item:clean_cloth", count=1),
                ItemStack(item="item:bucket", count=1),
            ],
            machine="crafting_table",
            priority=5,
        ),
        Recipe(
            id="meal",
            inputs=[
                ItemStack(item="item:clean_cloth", count=1),
                ItemStack(item="item:bucket", count=1),
            ],
            outputs=[ItemStack(item="item:meal", count=1)],
            machine="crafting_table",
            priority=1,
        ),
    ]


def resources_wash_meal() -> MemoryResourceProvider:
    return MemoryResourceProvider(
        {
            "item:dirty_cloth": 1,
            "item:water_bucket": 1,
            "item:clean_cloth": 0,
            "item:bucket": 0,
            "item:meal": 0,
        }
    )
