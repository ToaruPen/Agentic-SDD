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


# ============================================================================
# is_safe_repo_relative_root tests
# ============================================================================


def test_is_safe_repo_relative_root() -> None:
    assert MODULE.is_safe_repo_relative_root("docs")
    assert MODULE.is_safe_repo_relative_root("docs/sot")
    assert not MODULE.is_safe_repo_relative_root("../docs")
    assert not MODULE.is_safe_repo_relative_root("/")
    assert not MODULE.is_safe_repo_relative_root(".")


def test_is_safe_repo_relative_root_edge_cases() -> None:
    """Edge cases for path safety validation."""
    # Empty string
    assert not MODULE.is_safe_repo_relative_root("")
    # Path traversal attempts
    assert not MODULE.is_safe_repo_relative_root("..")
    assert not MODULE.is_safe_repo_relative_root("foo/..")
    assert not MODULE.is_safe_repo_relative_root("foo/../bar")
    # Valid nested paths
    assert MODULE.is_safe_repo_relative_root("a/b/c/d")
    # Paths with dots in names (valid)
    assert MODULE.is_safe_repo_relative_root("foo.bar")
    assert MODULE.is_safe_repo_relative_root("v1.0.0")


# ============================================================================
# extract_h2_section tests
# ============================================================================


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


def test_extract_h2_section_not_found() -> None:
    """Return empty string when section not found."""
    text = "## A\nfoo"
    section = MODULE.extract_h2_section(
        text, MODULE.re.compile(r"^\s*##\s*NOTFOUND\s*$", MODULE.re.MULTILINE)
    )
    assert section == ""


def test_extract_h2_section_last_section() -> None:
    """Extract section at end of document (no next H2)."""
    text = "## A\nfoo\n## B\nbar"
    section = MODULE.extract_h2_section(
        text, MODULE.re.compile(r"^\s*##\s*B\s*$", MODULE.re.MULTILINE)
    )
    assert "bar" in section
    assert "foo" not in section


# ============================================================================
# has_candidate_evidence_url tests
# ============================================================================


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


def test_has_candidate_evidence_url_multiple_urls() -> None:
    """Block with multiple URLs is valid."""
    block = """
候補-1
根拠リンク:
- https://example.com/a
- https://example.com/b
"""
    assert MODULE.has_candidate_evidence_url(block)


def test_has_candidate_evidence_url_empty_block() -> None:
    """Empty block has no evidence URL."""
    assert not MODULE.has_candidate_evidence_url("")


# ============================================================================
# _unique_ints tests (internal function - tested via lint_* functions)
# ============================================================================

# _unique_ints is an internal helper that accepts Iterable[re.Match[str]]
# It's tested indirectly through lint_research_contract and related functions.


# ============================================================================
# extract_labeled_block tests (pure function)
# ============================================================================


def test_extract_labeled_block_basic() -> None:
    """Extract content between labeled sections."""
    section = """
Start Label
content line 1
content line 2
End Label
other content
"""
    result = MODULE.extract_labeled_block(section, "Start Label", ["End Label"])
    assert "content line 1" in result
    assert "content line 2" in result
    assert "End Label" not in result
    assert "other content" not in result


def test_extract_labeled_block_not_found() -> None:
    """Return empty string when start label not found."""
    section = "Some content\nWithout labels"
    result = MODULE.extract_labeled_block(section, "Missing Label", ["End"])
    assert result == ""


def test_extract_labeled_block_no_end_label() -> None:
    """Extract until end when end label not found."""
    section = "Start Label\ncontent\nmore content"
    result = MODULE.extract_labeled_block(section, "Start Label", ["End Label"])
    assert "content" in result


# ============================================================================
# strip_fenced_code_blocks tests (pure function)
# ============================================================================


def test_strip_fenced_code_blocks_backticks() -> None:
    """Strip code blocks fenced with backticks."""
    text = "before\n```\ncode\n```\nafter"
    result = MODULE.strip_fenced_code_blocks(text)
    assert "before" in result
    assert "after" in result
    assert "code" not in result


def test_strip_fenced_code_blocks_tildes() -> None:
    """Strip code blocks fenced with tildes."""
    text = "before\n~~~\ncode\n~~~\nafter"
    result = MODULE.strip_fenced_code_blocks(text)
    assert "before" in result
    assert "after" in result
    assert "code" not in result


def test_strip_fenced_code_blocks_nested() -> None:
    """Handle nested fences with different lengths."""
    text = "````\nouter\n```\ninner\n```\nouter\n````"
    result = MODULE.strip_fenced_code_blocks(text)
    # Outer fence should be stripped entirely
    assert "outer" not in result
    assert "inner" not in result


def test_strip_fenced_code_blocks_no_fences() -> None:
    """Pass through text without fences unchanged."""
    text = "plain text\nmore text"
    result = MODULE.strip_fenced_code_blocks(text)
    assert result == text


# ============================================================================
# strip_indented_code_blocks tests (pure function)
# ============================================================================


def test_strip_indented_code_blocks_basic() -> None:
    """Strip 4-space indented code blocks."""
    text = "before\n    code line\nafter"
    result = MODULE.strip_indented_code_blocks(text)
    assert "before" in result
    assert "after" in result


def test_strip_indented_code_blocks_preserve_inline() -> None:
    """Preserve non-code indented content."""
    text = "normal\n    indented\nmore normal"
    result = MODULE.strip_indented_code_blocks(text)
    # Indented content should be stripped
    assert "normal" in result


# ============================================================================
# strip_inline_code_spans tests (pure function)
# ============================================================================


def test_strip_inline_code_spans_basic() -> None:
    """Strip inline code with backticks."""
    text = "before `code` after"
    result = MODULE.strip_inline_code_spans(text)
    assert "before" in result
    assert "after" in result
    assert "`code`" not in result


def test_strip_inline_code_spans_double_backticks() -> None:
    """Strip inline code with double backticks."""
    text = "before ``code with ` backtick`` after"
    result = MODULE.strip_inline_code_spans(text)
    assert "before" in result
    assert "after" in result


def test_strip_inline_code_spans_no_code() -> None:
    """Pass through text without inline code."""
    text = "plain text without code"
    result = MODULE.strip_inline_code_spans(text)
    assert result == text


# ============================================================================
# strip_html_comment_blocks tests (pure function)
# ============================================================================


def test_strip_html_comment_blocks_basic() -> None:
    """Strip HTML comment blocks."""
    text = "before<!-- comment -->after"
    result = MODULE.strip_html_comment_blocks(text)
    assert "before" in result
    assert "after" in result
    assert "comment" not in result


def test_strip_html_comment_blocks_multiline() -> None:
    """Strip multiline HTML comments."""
    text = "before<!--\nmultiline\ncomment\n-->after"
    result = MODULE.strip_html_comment_blocks(text)
    assert "before" in result
    assert "after" in result
    assert "multiline" not in result


# ============================================================================
# is_external_or_fragment tests (pure function)
# ============================================================================


def test_is_external_or_fragment_url() -> None:
    """URLs are external."""
    assert MODULE.is_external_or_fragment("https://example.com")
    assert MODULE.is_external_or_fragment("http://example.com")


def test_is_external_or_fragment_fragment() -> None:
    """Fragments are treated as external."""
    assert MODULE.is_external_or_fragment("#section")


def test_is_external_or_fragment_relative() -> None:
    """Relative paths are not external."""
    assert not MODULE.is_external_or_fragment("docs/readme.md")
    assert not MODULE.is_external_or_fragment("./file.md")


# ============================================================================
# normalize_target tests (pure function)
# ============================================================================


def test_normalize_target_relative() -> None:
    result = MODULE.normalize_target("./docs/readme.md")
    assert result == "./docs/readme.md"
    result2 = MODULE.normalize_target("docs/readme.md")
    assert result2 == "docs/readme.md"


def test_normalize_target_fragment() -> None:
    """Strip fragments from targets."""
    result = MODULE.normalize_target("docs/readme.md#section")
    assert result == "docs/readme.md"


def test_normalize_target_external() -> None:
    """External URLs pass through."""
    assert MODULE.normalize_target("https://example.com") == "https://example.com"


# ============================================================================
# parse_md_link_targets tests (pure function)
# ============================================================================


def test_parse_md_link_targets_basic() -> None:
    """Extract markdown link targets."""
    text = "[link](target.md) and [another](other.md)"
    result = MODULE.parse_md_link_targets(text)
    assert "target.md" in result
    assert "other.md" in result


def test_parse_md_link_targets_ignores_code() -> None:
    """Ignore links inside code blocks."""
    text = "```\n[code](ignored.md)\n```\n[valid](target.md)"
    result = MODULE.parse_md_link_targets(text)
    assert "ignored.md" not in result
    assert "target.md" in result


def test_parse_md_link_targets_empty() -> None:
    """Empty text yields no targets."""
    assert MODULE.parse_md_link_targets("") == []


# ============================================================================
# count_markdown_table_rows_with_headers tests (pure function)
# ============================================================================


def test_count_markdown_table_rows_basic() -> None:
    """Count table rows with matching headers."""
    section = """
| Name | Value |
|------|-------|
| foo  | bar   |
| baz  | qux   |
"""
    count = MODULE.count_markdown_table_rows_with_headers(section, ["Name", "Value"])
    assert count == 2


def test_count_markdown_table_rows_missing_header() -> None:
    section = """
| Wrong | Header |
|-------|--------|
| foo   | bar    |
"""
    count = MODULE.count_markdown_table_rows_with_headers(section, ["Name", "Value"])
    assert count == -1


def test_count_markdown_table_rows_empty() -> None:
    count = MODULE.count_markdown_table_rows_with_headers("", ["Name"])
    assert count == -1
