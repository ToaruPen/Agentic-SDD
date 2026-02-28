from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

# Add scripts directory to path for md_sanitize import
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "scripts"))




def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "lint-sot.py"
    spec = importlib.util.spec_from_file_location("lint_sot", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_extract_epic_config_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "extract-epic-config.py"
    spec = importlib.util.spec_from_file_location("extract_epic_config", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()
EXTRACT_EPIC_CONFIG_MODULE = load_extract_epic_config_module()


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


def test_extract_meta_info_ignores_status_in_fenced_code_and_html_comment() -> None:
    text = """
# Epic: Test

## メタ情報

- 作成日: 2026-02-20

```md
- ステータス: Approved
```

<!--
- ステータス: Approved
-->
"""
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] is None


def test_extract_meta_info_ignores_status_in_indented_code_block() -> None:
    text = """
# Epic: Test

## メタ情報

- 作成日: 2026-02-20

    - ステータス: Approved
"""
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] is None
