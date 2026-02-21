from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    scripts_dir = repo_root / "scripts"
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    module_path = scripts_dir / "assemble-sot.py"
    spec = importlib.util.spec_from_file_location("assemble_sot", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


class TestTruncateKeepTail:
    def test_short_text_unchanged(self) -> None:
        text = "short text"
        result = MODULE.truncate_keep_tail(text, max_chars=100)
        assert result == text

    def test_empty_text(self) -> None:
        result = MODULE.truncate_keep_tail("", max_chars=100)
        assert result == ""

    def test_exact_length(self) -> None:
        text = "a" * 100
        result = MODULE.truncate_keep_tail(text, max_chars=100)
        assert len(result) <= 100

    def test_truncation_adds_marker(self) -> None:
        text = "a" * 200
        result = MODULE.truncate_keep_tail(text, max_chars=100)
        assert "[TRUNCATED]" in result

    def test_zero_max_chars(self) -> None:
        text = "some text"
        result = MODULE.truncate_keep_tail(text, max_chars=0)
        assert result == text

    def test_preserves_tail(self) -> None:
        text = "header\n" + "x" * 200 + "\ntail content"
        result = MODULE.truncate_keep_tail(text, max_chars=100, tail_chars=30)
        assert "tail content" in result or "tail" in result


class TestSplitLevel2Sections:
    def test_single_section(self) -> None:
        text = "## Section1\ncontent1"
        pre, sections = MODULE.split_level2_sections(text)
        assert len(sections) == 1
        assert sections[0][0] == "## Section1"

    def test_multiple_sections(self) -> None:
        text = "## A\na\n## B\nb\n## C\nc"
        pre, sections = MODULE.split_level2_sections(text)
        assert len(sections) == 3

    def test_no_sections(self) -> None:
        text = "plain text\nno sections"
        pre, sections = MODULE.split_level2_sections(text)
        assert len(sections) == 0
        assert pre == text

    def test_preamble_preserved(self) -> None:
        text = "preamble\n## Section\ncontent"
        pre, sections = MODULE.split_level2_sections(text)
        assert "preamble" in pre

    def test_empty_text(self) -> None:
        pre, sections = MODULE.split_level2_sections("")
        assert pre == ""
        assert len(sections) == 0

    def test_section_body_included(self) -> None:
        text = "## Section\nline1\nline2\n## Next\nother"
        pre, sections = MODULE.split_level2_sections(text)
        assert "line1" in sections[0][1]
        assert "line2" in sections[0][1]


class TestExtractWideMarkdown:
    def test_single_section(self) -> None:
        text = "## Section\ncontent here"
        result = MODULE.extract_wide_markdown(text)
        assert "## Section" in result

    def test_empty_text(self) -> None:
        result = MODULE.extract_wide_markdown("")
        assert result.strip() == ""

    def test_preserves_h2_headers(self) -> None:
        text = "## A\na\n## B\nb"
        result = MODULE.extract_wide_markdown(text)
        assert "## A" in result
