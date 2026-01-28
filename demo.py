from __future__ import annotations

from models import ItemStack, Recipe
from providers.resource.memory import MemoryResourceProvider
from recipes import RecipeRegistry


def build_demo_recipes() -> RecipeRegistry:
    registry = RecipeRegistry()
    registry.add(
        Recipe(
            id="oak_planks",
            inputs=[ItemStack(item="minecraft:oak_log", count=1)],
            outputs=[ItemStack(item="minecraft:oak_planks", count=4)],
            machine="crafting_table",
            priority=10,
        )
    )
    registry.add(
        Recipe(
            id="sticks",
            inputs=[ItemStack(item="minecraft:oak_planks", count=2)],
            outputs=[ItemStack(item="minecraft:stick", count=4)],
            machine="crafting_table",
            priority=5,
        )
    )
    registry.add(
        Recipe(
            id="crafting_table",
            inputs=[
                ItemStack(item="minecraft:oak_planks", count=4),
                ItemStack(item="minecraft:stick", count=2),
            ],
            outputs=[ItemStack(item="minecraft:crafting_table", count=1)],
            machine="crafting_table",
            priority=1,
        )
    )
    return registry


def build_demo_resources() -> MemoryResourceProvider:
    return MemoryResourceProvider(
        {
            "minecraft:oak_log": 2,
            "minecraft:oak_planks": 0,
            "minecraft:stick": 0,
            "minecraft:crafting_table": 0,
        }
    )
