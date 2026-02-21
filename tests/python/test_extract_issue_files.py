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
    module_path = scripts_dir / "extract-issue-files.py"
    spec = importlib.util.spec_from_file_location("extract_issue_files", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


class TestIsSafeRepoRelative:
    def test_valid_path(self) -> None:
        assert MODULE.is_safe_repo_relative("docs/readme.md")
        assert MODULE.is_safe_repo_relative("src/lib.py")

    def test_empty_path(self) -> None:
        assert not MODULE.is_safe_repo_relative("")

    def test_absolute_path(self) -> None:
        assert not MODULE.is_safe_repo_relative("/etc/passwd")

    def test_parent_traversal(self) -> None:
        assert not MODULE.is_safe_repo_relative("..")
        assert not MODULE.is_safe_repo_relative("../foo")
        assert not MODULE.is_safe_repo_relative("foo/..")

    def test_current_directory(self) -> None:
        assert not MODULE.is_safe_repo_relative(".")


class TestNormalizeReference:
    def test_plain_path(self) -> None:
        assert MODULE.normalize_reference("docs/readme.md") == "docs/readme.md"

    def test_markdown_link(self) -> None:
        result = MODULE.normalize_reference("[link](target.md)")
        assert result == "target.md"

    def test_markdown_link_with_spaces(self) -> None:
        result = MODULE.normalize_reference("[text]( target.md )")
        assert result == "target.md"

    def test_backticks(self) -> None:
        result = MODULE.normalize_reference("`target.md`")
        assert result == "target.md"

    def test_whitespace_trimmed(self) -> None:
        result = MODULE.normalize_reference("  target.md  ")
        assert result == "target.md"

    def test_empty_string(self) -> None:
        result = MODULE.normalize_reference("")
        assert result == ""


class TestExtractSectionLines:
    def test_extracts_change_target_section(self) -> None:
        body = "## 変更対象ファイル\n- docs/a.md\n- docs/b.md\n## Other\ncontent"
        lines, found = MODULE.extract_section_lines(body)
        assert found
        assert any("docs/a.md" in line for line in lines)

    def test_extracts_english_change_target(self) -> None:
        body = "## Change targets\n- docs/a.md\n- docs/b.md"
        lines, found = MODULE.extract_section_lines(body)
        assert found

    def test_no_matching_heading(self) -> None:
        body = "## Other\ncontent"
        lines, found = MODULE.extract_section_lines(body)
        assert not found

    def test_empty_body(self) -> None:
        lines, found = MODULE.extract_section_lines("")
        assert not found
