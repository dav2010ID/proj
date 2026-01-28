from __future__ import annotations

import os


_DEBUG_ENABLED = os.environ.get("DEBUG", "").lower() in {"1", "true", "yes", "on"}


def debug(message: str) -> None:
    if _DEBUG_ENABLED:
        print(f"[DEBUG] {message}")


def info(message: str) -> None:
    print(f"[INFO] {message}")


def warn(message: str) -> None:
    print(f"[WARN] {message}")


def error(message: str) -> None:
    print(f"[ERROR] {message}")
