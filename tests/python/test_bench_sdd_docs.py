from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "lint" / "bench_sdd_docs.py"
    spec = importlib.util.spec_from_file_location("bench_sdd_docs", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_main_rejects_zero_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        ["bench_sdd_docs.py", "--timeout", "0"],
    )
    with pytest.raises(SystemExit) as excinfo:
        MODULE.main()
    assert excinfo.value.code == 2


def test_main_rejects_negative_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        ["bench_sdd_docs.py", "--timeout", "-1"],
    )
    with pytest.raises(SystemExit) as excinfo:
        MODULE.main()
    assert excinfo.value.code == 2
