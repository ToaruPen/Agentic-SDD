from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "bench-sdd-docs.py"
    spec = importlib.util.spec_from_file_location("bench_sdd_docs", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_commands_include_test_review() -> None:
    assert "/test-review" in MODULE.COMMANDS


def test_commands_include_pr_bots_review() -> None:
    assert "/pr-bots-review" in MODULE.COMMANDS
