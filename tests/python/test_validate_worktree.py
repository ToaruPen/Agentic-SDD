from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "validate-worktree.py"
    spec = importlib.util.spec_from_file_location("validate_worktree", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_extract_issue_number_from_branch() -> None:
    assert MODULE.extract_issue_number_from_branch("feature/issue-120-foo") == 120
    assert MODULE.extract_issue_number_from_branch("hotfix/issue-1") == 1
    assert MODULE.extract_issue_number_from_branch("feature/no-issue") is None


def test_is_linked_worktree_gitfile() -> None:
    linked = "gitdir: /repo/.git/worktrees/issue-120\n"
    plain = "gitdir: /repo/.git\n"
    assert MODULE.is_linked_worktree_gitfile(linked)
    assert not MODULE.is_linked_worktree_gitfile(plain)
