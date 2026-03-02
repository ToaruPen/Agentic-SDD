from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "lint" / "assemble_sot.py"
    spec = importlib.util.spec_from_file_location("assemble_sot", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()
MARKER = "\n\n[TRUNCATED]\n\n"


def test_truncate_keep_tail_returns_original_when_max_non_positive() -> None:
    text = "abc\ndef\n"
    assert MODULE.truncate_keep_tail(text, 0) == text
    assert MODULE.truncate_keep_tail(text, -1) == text


def test_truncate_keep_tail_returns_original_when_within_limit() -> None:
    text = "short text\n"
    assert MODULE.truncate_keep_tail(text, len(text)) == text
    assert MODULE.truncate_keep_tail(text, len(text) + 5) == text


def test_truncate_keep_tail_small_budget_uses_marker_slice() -> None:
    text = "x" * 200
    out = MODULE.truncate_keep_tail(text, 5)
    assert len(out) == 5
    assert out.endswith("\n")


def test_truncate_keep_tail_preserves_tail_without_newlines() -> None:
    text = "a" * 120 + "TAILEND"
    out = MODULE.truncate_keep_tail(text, 40, tail_chars=8)
    assert len(out) <= 40
    assert out.endswith("\n")
    assert "TAILEN" in out
    assert MARKER in out


def test_truncate_keep_tail_prefers_line_boundaries() -> None:
    text = "line1\nline2\nline3\nline4\nline5\n"
    out = MODULE.truncate_keep_tail(text, 28, tail_chars=12)
    assert len(out) <= 28
    assert MARKER in out
    head, tail = out.split(MARKER, 1)
    if len(head) > 1:
        assert head.endswith("\n")
    assert out.endswith("\n")
    assert not tail.startswith("ine")
