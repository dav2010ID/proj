from __future__ import annotations

from typing import Dict, List

from models import Recipe
from util.itemkey import normalize


class RecipeRegistry:
    def __init__(self) -> None:
        self._recipes: List[Recipe] = []
        self._index: Dict[str, List[Recipe]] = {}

    def add(self, recipe: Recipe) -> None:
        self._recipes.append(recipe)

    def rebuild_index(self) -> Dict[str, List[Recipe]]:
        index: Dict[str, List[Recipe]] = {}
        for recipe in self._recipes:
            for output in recipe.outputs:
                key = normalize(output.item)
                index.setdefault(key, []).append(recipe)
        self._index = index
        return index

    def get_producers(self, item_key: str) -> List[Recipe]:
        key = normalize(item_key)
        return list(self._index.get(key, []))

    @property
    def recipes(self) -> List[Recipe]:
        return list(self._recipes)
