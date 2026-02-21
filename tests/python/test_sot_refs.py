from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "sot_refs.py"
    spec = importlib.util.spec_from_file_location("sot_refs", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


class TestIsSafeRepoRelative:
    def test_valid_relative_path(self) -> None:
        assert MODULE.is_safe_repo_relative("docs/readme.md")
        assert MODULE.is_safe_repo_relative("src/lib/module.py")
        assert MODULE.is_safe_repo_relative("a/b/c/d/e")

    def test_empty_string(self) -> None:
        assert not MODULE.is_safe_repo_relative("")

    def test_absolute_path(self) -> None:
        assert not MODULE.is_safe_repo_relative("/etc/passwd")
        assert not MODULE.is_safe_repo_relative("/home/user/file")

    def test_parent_traversal(self) -> None:
        assert not MODULE.is_safe_repo_relative("..")
        assert not MODULE.is_safe_repo_relative("../etc")
        assert not MODULE.is_safe_repo_relative("foo/..")
        assert not MODULE.is_safe_repo_relative("foo/../bar")
        assert not MODULE.is_safe_repo_relative("a/b/../../../etc")

    def test_current_directory(self) -> None:
        assert not MODULE.is_safe_repo_relative(".")
        assert not MODULE.is_safe_repo_relative("..")

    def test_path_with_dots_in_name(self) -> None:
        assert MODULE.is_safe_repo_relative("v1.0.0")
        assert MODULE.is_safe_repo_relative("foo.bar")
        assert MODULE.is_safe_repo_relative("file.test.md")


class TestNormalizeReference:
    def test_plain_path(self) -> None:
        assert MODULE.normalize_reference("docs/readme.md") == "docs/readme.md"

    def test_markdown_link(self) -> None:
        result = MODULE.normalize_reference("[click here](target.md)")
        assert result == "target.md"

    def test_markdown_link_with_spaces(self) -> None:
        result = MODULE.normalize_reference("[text]( target.md )")
        assert result == "target.md"

    def test_angle_brackets(self) -> None:
        result = MODULE.normalize_reference("<target.md>")
        assert result == "target.md"

    def test_backticks(self) -> None:
        result = MODULE.normalize_reference("`target.md`")
        assert result == "target.md"

    def test_fragment_stripped(self) -> None:
        result = MODULE.normalize_reference("target.md#section")
        assert result == "target.md"

    def test_whitespace_trimmed(self) -> None:
        result = MODULE.normalize_reference("  target.md  ")
        assert result == "target.md"


class TestFindIssueRef:
    def test_find_epic_ref(self) -> None:
        body = "- Epic: docs/epics/test.md\n- PRD: docs/prd/test.md"
        result = MODULE.find_issue_ref(body, "Epic")
        assert result == "docs/epics/test.md"

    def test_find_prd_ref(self) -> None:
        body = "- Epic: docs/epics/test.md\n- PRD: docs/prd/test.md"
        result = MODULE.find_issue_ref(body, "PRD")
        assert result == "docs/prd/test.md"

    def test_case_insensitive(self) -> None:
        body = "- epic: docs/epics/test.md"
        result = MODULE.find_issue_ref(body, "Epic")
        assert result == "docs/epics/test.md"

    def test_not_found(self) -> None:
        body = "Some content without refs"
        result = MODULE.find_issue_ref(body, "Epic")
        assert result is None

    def test_asterisk_bullet(self) -> None:
        body = "* Epic: docs/epics/test.md"
        result = MODULE.find_issue_ref(body, "Epic")
        assert result == "docs/epics/test.md"

    def test_empty_body(self) -> None:
        result = MODULE.find_issue_ref("", "Epic")
        assert result is None
