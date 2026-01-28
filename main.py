from __future__ import annotations

import sys

from executor import execute
from machines import MachineInstance, MachineAllocator, MachineState
from planner import plan
from providers.machine.crafting_table import CraftingTableProvider
from demo import build_demo_recipes, build_demo_resources
from util.log import debug, error, info


def craft_item(item: str, count: int, plan_only: bool) -> int:
    registry = build_demo_recipes()
    resources = build_demo_resources()
    pool = MachineAllocator(
        [
            MachineInstance(
                id="crafting_table_1",
                type="crafting_table",
                provider=CraftingTableProvider(),
                state=MachineState(),
            ),
        ]
    )

    recipes_by_output = registry.rebuild_index()
    ok, plan_or_err = plan(item, count, recipes_by_output, resources)
    if not ok:
        error(f"Plan failed: {plan_or_err}")
        return 1
    debug(f"main plan steps={len(plan_or_err)}")

    if plan_only:
        info("Plan complete")
        return 0

    ok, err = execute(plan_or_err, resources, pool)
    if not ok:
        error(f"Execution failed: {err}")
        return 1

    info("Execution complete")
    info(f"Remaining stock: {resources.snapshot()}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: python main.py <craft|plan> <item> <count>")
        return 1

    cmd = argv[1]
    if cmd not in {"craft", "plan"}:
        print("Command must be 'craft' or 'plan'")
        return 1

    if len(argv) < 3:
        print("Missing item")
        return 1

    item = argv[2]
    count = int(argv[3]) if len(argv) > 3 else 1

    return craft_item(item, count, plan_only=(cmd == "plan"))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
