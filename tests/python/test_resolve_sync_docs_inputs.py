from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "extract" / "resolve_sync_docs_inputs.py"
    spec = importlib.util.spec_from_file_location(
        "resolve_sync_docs_inputs", module_path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_git_has_diff_returns_false_when_clean() -> None:
    result = SimpleNamespace(returncode=0)
    monkeypatch = pytest.MonkeyPatch()
    try:
        monkeypatch.setattr(MODULE.shutil, "which", lambda _: "/usr/bin/git")
        monkeypatch.setattr(MODULE, "run", lambda *_, **__: result)
        assert MODULE.git_has_diff(".", []) is False
    finally:
        monkeypatch.undo()


def test_git_has_diff_returns_true_when_dirty() -> None:
    result = SimpleNamespace(returncode=1)
    monkeypatch = pytest.MonkeyPatch()
    try:
        monkeypatch.setattr(MODULE.shutil, "which", lambda _: "/usr/bin/git")
        monkeypatch.setattr(MODULE, "run", lambda *_, **__: result)
        assert MODULE.git_has_diff(".", ["--cached"]) is True
    finally:
        monkeypatch.undo()


def test_git_has_diff_raises_runtime_error_for_execution_error() -> None:
    result = SimpleNamespace(returncode=2)
    monkeypatch = pytest.MonkeyPatch()
    try:
        monkeypatch.setattr(MODULE.shutil, "which", lambda _: "/usr/bin/git")
        monkeypatch.setattr(MODULE, "run", lambda *_, **__: result)
        with pytest.raises(RuntimeError, match="failed with exit code 2"):
            MODULE.git_has_diff(".", [])
    finally:
        monkeypatch.undo()


def test_git_has_diff_raises_runtime_error_for_signal_termination() -> None:
    result = SimpleNamespace(returncode=-9)
    monkeypatch = pytest.MonkeyPatch()
    try:
        monkeypatch.setattr(MODULE.shutil, "which", lambda _: "/usr/bin/git")
        monkeypatch.setattr(MODULE, "run", lambda *_, **__: result)
        with pytest.raises(RuntimeError, match="terminated by signal 9"):
            MODULE.git_has_diff(".", [])
    finally:
        monkeypatch.undo()
