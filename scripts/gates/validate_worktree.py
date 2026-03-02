#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import re

from _lib.git_utils import (
    current_branch,
    eprint,
    extract_issue_number_from_branch,
    git_repo_root,
    run,
)

EXIT_GATE_BLOCKED = 2
_ = run


def gate_blocked(msg: str) -> int:
    eprint("[agentic-sdd gate] BLOCKED")
    eprint("")
    eprint(msg.rstrip())
    eprint("")
    return EXIT_GATE_BLOCKED


def is_linked_worktree_gitfile(content: str) -> bool:
    return bool(re.search(r"\.git/worktrees/", content))


def main() -> int:
    try:
        repo_root = git_repo_root()
    except RuntimeError:
        return 0

    try:
        branch = current_branch(repo_root)
    except RuntimeError as exc:
        return gate_blocked(f"Failed to detect current branch via git.\n- error: {exc}")
    issue_number = extract_issue_number_from_branch(branch)

    if issue_number is None:
        return 0

    git_path = Path(repo_root) / ".git"
    if git_path.is_file():
        try:
            content = git_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return gate_blocked(f"Failed to read .git file.\n- error: {exc}")

        if is_linked_worktree_gitfile(content):
            return 0

        return gate_blocked(
            "Worktree is required for Issue branches (non-worktree gitdir detected).\n"
            f"- branch: {branch}\n"
            f"- path: {git_path}"
        )

    if git_path.is_dir():
        return gate_blocked(
            "Worktree is required for Issue branches.\n"
            f"- branch: {branch}\n"
            f"- expected: a linked worktree created via /worktree (so .git is a file)\n"
            "\n"
            "Next action:\n"
            f'1) Run: /worktree new --issue {issue_number} --desc "<ascii short desc>"\n'
            "2) Switch into that worktree directory\n"
            "3) Run: /estimation, then /impl or /tdd"
        )

    return gate_blocked(
        "Failed to determine git worktree state (.git path missing).\n"
        f"- branch: {branch}\n"
        f"- path: {git_path}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
