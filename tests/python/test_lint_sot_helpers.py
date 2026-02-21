from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "lint-sot.py"
    spec = importlib.util.spec_from_file_location("lint_sot", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_is_safe_repo_relative_root() -> None:
    assert MODULE.is_safe_repo_relative_root("docs")
    assert MODULE.is_safe_repo_relative_root("docs/sot")
    assert not MODULE.is_safe_repo_relative_root("../docs")
    assert not MODULE.is_safe_repo_relative_root("/")
    assert not MODULE.is_safe_repo_relative_root(".")


def test_extract_h2_section() -> None:
    text = """
## A
foo
## B
bar
"""
    section = MODULE.extract_h2_section(
        text, MODULE.re.compile(r"^\s*##\s*A\s*$", MODULE.re.MULTILINE)
    )
    assert "foo" in section
    assert "bar" not in section


def test_has_candidate_evidence_url() -> None:
    block_ok = """
候補-1
概要: x
適用可否: Yes
仮説: x
反証: x
採否理由: x
根拠リンク:
- https://example.com/a
捨て条件: x
リスク/検証: x
"""
    block_ng = """
候補-1
概要: x
適用可否: Yes
仮説: x
反証: x
採否理由: x
根拠リンク:
捨て条件: x
リスク/検証: x
"""
    assert MODULE.has_candidate_evidence_url(block_ok)
    assert not MODULE.has_candidate_evidence_url(block_ng)
