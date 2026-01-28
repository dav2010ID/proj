import unittest

from models import CraftStep, ItemStack, Recipe, SupplyStep


class ModelsTest(unittest.TestCase):
    def test_itemstack_rejects_non_positive_count(self) -> None:
        with self.assertRaises(ValueError):
            ItemStack(item="item:a", count=0)
        with self.assertRaises(ValueError):
            ItemStack(item="item:a", count=-1)

    def test_itemstack_normalizes_item(self) -> None:
        stack = ItemStack(item=" item:a ", count=1)
        self.assertEqual(stack.item, "item:a")

    def test_recipe_requires_outputs(self) -> None:
        with self.assertRaises(ValueError):
            Recipe(id="r", inputs=[], outputs=[], machine="m")

    def test_supplystep_requires_positive_count(self) -> None:
        with self.assertRaises(ValueError):
            SupplyStep(item="item:a", count=0)

    def test_craftstep_requires_positive_times(self) -> None:
        recipe = Recipe(
            id="r",
            inputs=[ItemStack(item="item:a", count=1)],
            outputs=[ItemStack(item="item:b", count=1)],
            machine="m",
        )
        with self.assertRaises(ValueError):
            CraftStep(recipe=recipe, times=0)


if __name__ == "__main__":
    unittest.main()
