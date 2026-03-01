from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

from _lib.subprocess_utils import run_cmd


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: list[str],
    cwd: str | os.PathLike[str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    cwd_str = os.fspath(cwd) if cwd is not None else None
    return run_cmd(cmd, cwd=cwd_str, check=check)


def repo_root() -> str | None:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=False)
    except OSError:
        return None
    root = (p.stdout or "").strip()
    if not root:
        return None
    return str(Path(root).resolve())


def git_repo_root() -> str:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=True)
    except (subprocess.CalledProcessError, OSError) as exc:
        raise RuntimeError("Not in a git repository; cannot locate repo root.") from exc
    root = p.stdout.strip()
    if not root:
        raise RuntimeError("Failed to locate repo root via git.")
    return str(Path(root).resolve())


def current_branch(repo_root: str) -> str:
    try:
        p = run(["git", "branch", "--show-current"], cwd=repo_root, check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError("Failed to detect current branch via git.") from exc
    branch = p.stdout.strip()
    if not branch:
        raise RuntimeError("Failed to detect current branch via git.")
    return branch


def extract_issue_number_from_branch(branch: str) -> int | None:
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
