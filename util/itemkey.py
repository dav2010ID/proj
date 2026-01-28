from __future__ import annotations

from typing import Any


def normalize(stack_or_name: Any) -> str:
    if isinstance(stack_or_name, str):
        return stack_or_name.strip()
    if hasattr(stack_or_name, "item"):
        return str(getattr(stack_or_name, "item")).strip()
    if isinstance(stack_or_name, dict):
        if "item" in stack_or_name:
            return str(stack_or_name["item"]).strip()
        if "name" in stack_or_name:
            return str(stack_or_name["name"]).strip()
    raise TypeError("Unsupported item key input")


def same(a: Any, b: Any) -> bool:
    return normalize(a) == normalize(b)


def to_string(item_key: Any) -> str:
    return normalize(item_key)
