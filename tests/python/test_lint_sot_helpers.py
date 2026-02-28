from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def _load_script_module(module_name: str, script_name: str) -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / script_name
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = _load_script_module("lint_sot", "lint-sot.py")
EXTRACT_EPIC_CONFIG_MODULE = _load_script_module(
    "extract_epic_config", "extract-epic-config.py"
)


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


def test_extract_meta_info_returns_real_status_ignoring_distractors() -> None:
    text = """
# Epic: Test

```md
- ステータス: Approved
```

<!--
- ステータス: Approved
-->

- ステータス: Draft
"""
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] == "Draft"


def test_extract_meta_info_ignores_status_in_tilde_fenced_code() -> None:
    text = """
# Epic: Test

## メタ情報

- 作成日: 2026-02-20

~~~md
- ステータス: Approved
~~~
"""
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] is None


def test_lint_status_format_detects_nested_status() -> None:
    text = """
# Epic: Test

## メタ情報

- メタ:
    - ステータス: Approved
    - 参照PRD: docs/prd/test.md
"""
    errs = MODULE.lint_status_format("docs/epics/test.md", text)
    assert len(errs) == 1
    assert "ステータス行がインデント" in errs[0].message


def test_lint_status_format_ok_for_toplevel_status() -> None:
    text = """
# Epic: Test

## メタ情報

- ステータス: Approved
- 参照PRD: `docs/prd/test.md`
"""
    errs = MODULE.lint_status_format("docs/epics/test.md", text)
    assert len(errs) == 0


def test_extract_meta_info_ignores_status_after_escaped_backtick_comment() -> None:
    """Escaped backticks (\\`) do not form inline code spans.

    So `\\`<!-- ... \\`` should NOT mask the `<!--`; the `<!--`
    is a genuine HTML comment opener and everything after it is
    stripped.  The Approved status that follows should be invisible.
    """
    text = (
        "# Epic: Test\n"
        "\n"
        "## メタ情報\n"
        "\n"
        "- 作成日: 2026-02-20\n"
        "\n"
        "Here is an escaped backtick \\`<!-- and another \\`\n"
        "\n"
        "- ステータス: Approved\n"
    )
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] is None


def test_extract_meta_info_code_span_backslash_before_comment() -> None:
    r"""Code span ```` `\` ```` closes at the inner backtick per CommonMark.

    Inside a code span backslash is literal, so ``\`` is a code span
    containing just a backslash.  The ``<!--`` that follows is a real
    HTML comment opener and the Approved status after it must be
    stripped.
    """
    text = (
        "# Epic: Test\n"
        "\n"
        "## メタ情報\n"
        "\n"
        "- 作成日: 2026-02-20\n"
        "\n"
        "`\\`<!--`\n"
        "\n"
        "- ステータス: Approved\n"
    )
    meta = EXTRACT_EPIC_CONFIG_MODULE.extract_meta_info(text)
    assert meta["status"] is None
