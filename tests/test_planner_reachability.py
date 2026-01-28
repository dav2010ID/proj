import unittest

from models import ItemStack, Recipe
from planner import compute_reachable
from providers.resource.memory import MemoryResourceProvider
from recipes import RecipeRegistry


class PlannerReachabilityTest(unittest.TestCase):
    def test_compute_reachable_ignores_unrelated_items(self) -> None:
        registry = RecipeRegistry()
        registry.add(
            Recipe(
                id="make_target",
                inputs=[ItemStack(item="item:input", count=1)],
                outputs=[ItemStack(item="item:target", count=1)],
                machine="crafting_table",
            )
        )
        registry.add(
            Recipe(
                id="unused",
                inputs=[ItemStack(item="item:unused_in", count=1)],
                outputs=[ItemStack(item="item:unused_out", count=1)],
                machine="crafting_table",
            )
        )
        registry.rebuild_index()

        reachable = compute_reachable("item:target", registry.rebuild_index())
        self.assertIn("item:target", reachable)
        self.assertIn("item:input", reachable)
        self.assertNotIn("item:unused_out", reachable)
        self.assertNotIn("item:unused_in", reachable)

    def test_memory_provider_snapshot_freezes_new_items(self) -> None:
        provider = MemoryResourceProvider({"item:a": 1})
        provider.prepare({"item:a"})
        provider.snapshot()
        with self.assertRaises(RuntimeError):
            provider.get("item:b")


if __name__ == "__main__":
    unittest.main()
