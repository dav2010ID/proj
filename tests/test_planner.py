import unittest

from models import CraftStep, SupplyStep
from planner import plan
from providers.resource.memory import MemoryResourceProvider
from tests.fixtures import (
    recipes_gear_alternatives,
    recipes_sticks_from_planks,
    recipes_wash_meal,
    registry_from_recipes,
    resources_wash_meal,
)


class PlannerEdgeCasesTest(unittest.TestCase):
    def test_item_already_in_stock(self) -> None:
        registry = registry_from_recipes([])
        resources = MemoryResourceProvider({"item:a": 3})

        ok, plan_or_err = plan("item:a", 3, registry.rebuild_index(), resources)
        self.assertTrue(ok, plan_or_err)
        steps = plan_or_err
        self.assertEqual(len(steps), 1)
        self.assertIsInstance(steps[0], SupplyStep)
        self.assertEqual(steps[0].item, "item:a")
        self.assertEqual(steps[0].count, 3)

    def test_partial_inventory_uses_stock_then_crafts(self) -> None:
        registry = registry_from_recipes(recipes_sticks_from_planks())
        resources = MemoryResourceProvider({"item:planks": 2, "item:sticks": 0})

        ok, plan_or_err = plan("item:sticks", 4, registry.rebuild_index(), resources)
        self.assertTrue(ok, plan_or_err)
        steps = plan_or_err
        self.assertIsInstance(steps[0], SupplyStep)
        self.assertEqual(steps[0].item, "item:planks")
        self.assertEqual(steps[0].count, 2)
        self.assertIsInstance(steps[1], CraftStep)
        self.assertEqual(steps[1].recipe.id, "sticks")
        self.assertEqual(steps[1].times, 1)

    def test_alternative_recipe_no_backtracking(self) -> None:
        registry = registry_from_recipes(recipes_gear_alternatives())
        resources = MemoryResourceProvider({"item:iron": 1, "item:gear": 0})

        ok, plan_or_err = plan("item:gear", 1, registry.rebuild_index(), resources)
        self.assertFalse(ok)
        self.assertEqual(plan_or_err, "no_recipe_or_stock")

    def test_recipe_with_container_return(self) -> None:
        registry = registry_from_recipes(recipes_wash_meal())
        resources = resources_wash_meal()

        ok, plan_or_err = plan("item:meal", 1, registry.rebuild_index(), resources)
        self.assertTrue(ok, plan_or_err)
        steps = plan_or_err

        supply_items = {step.item for step in steps if isinstance(step, SupplyStep)}
        self.assertIn("item:dirty_cloth", supply_items)
        self.assertIn("item:water_bucket", supply_items)
        self.assertNotIn("item:bucket", supply_items)

        craft_ids = [step.recipe.id for step in steps if isinstance(step, CraftStep)]
        self.assertEqual(craft_ids, ["wash", "meal"])


if __name__ == "__main__":
    unittest.main()
