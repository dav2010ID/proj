from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from models import CraftStep, PlanStep, Recipe, SupplyStep
from util.itemkey import normalize
from util.log import debug, info


@dataclass
class PlanContext:
    resource: object
    recipes: Dict[str, List[Recipe]]
    reachable: Set[str] = field(default_factory=set)
    virtual_stock: Dict[str, int] = field(default_factory=dict)
    initial_stock: Dict[str, int] = field(default_factory=dict)
    stock_remaining: Dict[str, int] = field(default_factory=dict)
    stack: Set[str] = field(default_factory=set)
    plan: List[PlanStep] = field(default_factory=list)


def select_recipe(recipes: List[Recipe]) -> Recipe:
    return sorted(recipes, key=lambda r: r.priority, reverse=True)[0]


def get_virtual_stock(ctx: PlanContext, item: str) -> int:
    if item not in ctx.virtual_stock:
        raise RuntimeError("item_not_initialized")
    return int(ctx.virtual_stock[item])


def compute_reachable(target_item_key: str, recipes_by_output: Dict[str, List[Recipe]]) -> Set[str]:
    reachable: Set[str] = set()

    def dfs_item(item_key: str) -> None:
        key = normalize(item_key)
        if key in reachable:
            return
        reachable.add(key)
        for recipe in recipes_by_output.get(key, []):
            for stack in recipe.inputs:
                dfs_item(stack.item)

    dfs_item(target_item_key)
    return reachable


def initialize_stock(ctx: PlanContext, reachable_items: Set[str]) -> None:
    for item in reachable_items:
        value = int(ctx.resource.get(item))
        ctx.initial_stock[item] = value
        ctx.virtual_stock[item] = value
        ctx.stock_remaining[item] = value


def get_output_for_item(recipe: Recipe, item: str):
    for output in recipe.outputs:
        if normalize(output.item) == item:
            return output
    return None


def plan_need(ctx: PlanContext, item: str, count: int) -> Tuple[bool, str | None]:
    item = normalize(item)
    debug(f"plan_need start item={item} count={count}")
    if item in ctx.stack:
        return False, "cycle"
    if item not in ctx.reachable:
        return False, "item_not_reachable"

    try:
        available = get_virtual_stock(ctx, item)
    except RuntimeError:
        return False, "item_not_initialized"
    use = min(count, max(0, available))
    if use > 0:
        from_stock = min(use, ctx.stock_remaining.get(item, 0))
        if from_stock > 0:
            ctx.stock_remaining[item] -= from_stock
            if ctx.stock_remaining[item] < 0:
                return False, "supply_exceeds_stock"
            ctx.plan.append(SupplyStep(item=item, count=from_stock))
            debug(f"plan_need supply item={item} count={from_stock}")
        ctx.virtual_stock[item] = available - use
        if ctx.virtual_stock[item] < 0:
            return False, "virtual_stock_negative"
        debug(f"plan_need consume item={item} use={use} stock_before={available}")

    remain = count - use

    if remain == 0:
        debug(f"plan_need satisfied item={item}")
        return True, None

    recipes = ctx.recipes.get(item)
    if not recipes:
        debug(f"plan_need no recipe for item={item} remain={remain}")
        return False, "no_recipe_or_stock"

    ctx.stack.add(item)
    try:
        recipe = select_recipe(recipes)
        debug(f"plan_need selected recipe={recipe.id} for item={item}")
        out = get_output_for_item(recipe, item)
        if out is None or out.count <= 0:
            return False, "no_matching_output"
        times = (remain + out.count - 1) // out.count
        debug(f"plan_need recipe={recipe.id} times={times} out_count={out.count} remain={remain}")

        for input_item in recipe.inputs:
            debug(f"plan_need need input item={input_item.item} count={input_item.count * times}")
            ok, err = plan_need(ctx, input_item.item, input_item.count * times)
            if not ok:
                return False, err

        ctx.plan.append(CraftStep(recipe=recipe, times=times))

        for output in recipe.outputs:
            out_item = normalize(output.item)
            produced_count = output.count * times
            current = ctx.virtual_stock.get(out_item, 0)
            ctx.virtual_stock[out_item] = current + produced_count
            debug(f"plan_need produced item={output.item} count={produced_count}")

        current_item = get_virtual_stock(ctx, item)
        if __debug__:
            assert current_item - remain >= 0
        ctx.virtual_stock[item] = current_item - remain
        debug(f"plan_need consume produced item={item} count={remain}")
    finally:
        ctx.stack.discard(item)

    return True, None


def compress_supplies(plan: List[PlanStep]) -> List[PlanStep]:
    totals: Dict[str, int] = {}
    order: List[str] = []
    crafts: List[PlanStep] = []

    for step in plan:
        if isinstance(step, SupplyStep):
            if step.item not in totals:
                order.append(step.item)
                totals[step.item] = 0
            totals[step.item] += step.count
        else:
            crafts.append(step)

    debug(f"compress_supplies merged_items={len(order)}")
    merged_supplies = [
        SupplyStep(item=item, count=totals[item])
        for item in order
        if totals[item] > 0
    ]
    return merged_supplies + crafts


def compress_crafts(plan: List[PlanStep]) -> List[PlanStep]:
    merged: List[PlanStep] = []
    merged_count = 0
    for step in plan:
        if not isinstance(step, CraftStep):
            merged.append(step)
            continue
        last = merged[-1] if merged else None
        if (
            last
            and isinstance(last, CraftStep)
            and last.recipe.id == step.recipe.id
            and last.recipe.machine == step.recipe.machine
        ):
            merged[-1] = CraftStep(recipe=last.recipe, times=last.times + step.times)
            merged_count += 1
            continue
        merged.append(step)
    debug(f"compress_crafts merged_steps={merged_count}")
    return merged


def plan(target_item_key: str, target_count: int, recipes_by_output: Dict[str, List[Recipe]], resource_provider: object) -> Tuple[bool, List[PlanStep] | str]:
    reachable = compute_reachable(target_item_key, recipes_by_output)
    ctx = PlanContext(resource=resource_provider, recipes=recipes_by_output, reachable=reachable)
    debug(f"plan start target={target_item_key} count={target_count}")
    if hasattr(resource_provider, "prepare"):
        resource_provider.prepare(reachable)
    initialize_stock(ctx, reachable)
    if hasattr(resource_provider, "snapshot"):
        resource_provider.snapshot()
    ok, err = plan_need(ctx, target_item_key, target_count)
    if not ok:
        return False, err or "plan_failed"

    if __debug__:
        target_item = normalize(target_item_key)
        assert ctx.virtual_stock.get(target_item, 0) >= 0
        for value in ctx.virtual_stock.values():
            assert value >= 0
        for value in ctx.stock_remaining.values():
            assert value >= 0

    ctx.plan = compress_supplies(ctx.plan)
    ctx.plan = compress_crafts(ctx.plan)

    for step in ctx.plan:
        if isinstance(step, SupplyStep):
            info(f"PLAN supply {step.item} x{step.count}")
        elif isinstance(step, CraftStep):
            info(f"PLAN craft {step.recipe.id} x{step.times}")

    return True, ctx.plan
