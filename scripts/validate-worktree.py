#!/usr/bin/env python3

import os
import re
import subprocess
import sys
from typing import List, Optional

EXIT_GATE_BLOCKED = 2


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: List[str],
    cwd: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def git_repo_root() -> str:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=True)
    except subprocess.CalledProcessError:
        raise RuntimeError("Not in a git repository; cannot locate repo root.")
    root = p.stdout.strip()
    if not root:
        raise RuntimeError("Failed to locate repo root via git.")
    return os.path.realpath(root)


def current_branch(repo_root: str) -> str:
    try:
        p = run(["git", "branch", "--show-current"], cwd=repo_root, check=False)
    except subprocess.CalledProcessError:
        return ""
    return p.stdout.strip()


def extract_issue_number_from_branch(branch: str) -> Optional[int]:
    m = re.search(r"\bissue-(\d+)\b", branch)
    if not m:
        return None
    try:
        n = int(m.group(1))
    except ValueError:
        return None
    if n < 0:
        return None
    return n


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
    except Exception:
        return 0

    branch = current_branch(repo_root)
    issue_number = extract_issue_number_from_branch(branch)

    if issue_number is None:
        return 0

    git_path = os.path.join(repo_root, ".git")
    if os.path.isfile(git_path):
        try:
            with open(git_path, "r", encoding="utf-8") as fh:
                content = fh.read()
        except OSError as exc:
            return gate_blocked(f"Failed to read .git file.\n- error: {exc}")

        if is_linked_worktree_gitfile(content):
            return 0

        return gate_blocked(
            "Worktree is required for Issue branches (non-worktree gitdir detected).\n"
            f"- branch: {branch}\n"
            f"- path: {git_path}"
        )

    if os.path.isdir(git_path):
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
