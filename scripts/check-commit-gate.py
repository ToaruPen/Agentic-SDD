#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from typing import List, Optional


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


def repo_root() -> Optional[str]:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=False)
    except Exception:
        return None
    root = (p.stdout or "").strip()
    if not root:
        return None
    return os.path.realpath(root)


def should_check_command(command: str) -> bool:
    """Check if the command is a git commit or git push command."""
    keywords = ["git commit", "git push"]
    return any(keyword in command for keyword in keywords)


def main() -> int:
    # Read hook input from stdin
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        # If no valid JSON input, skip the check
        return 0

    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    # Only check git commit/push commands
    if not should_check_command(command):
        return 0
    root = repo_root()
    if not root:
        return 0

    worktree_gate = os.path.join(root, "scripts", "validate-worktree.py")
    if os.path.isfile(worktree_gate):
        try:
            p = run([sys.executable, worktree_gate], cwd=root, check=False)
        except Exception as exc:  # noqa: BLE001
            eprint(f"[agentic-sdd gate] error: {exc}")
            return 1
        if p.stdout:
            sys.stdout.write(p.stdout)
        if p.stderr:
            sys.stderr.write(p.stderr)
        if p.returncode != 0:
            return p.returncode

    script = os.path.join(root, "scripts", "validate-approval.py")
    if not os.path.isfile(script):
        return 0

    try:
        p = run([sys.executable, script], cwd=root, check=False)
    except Exception as exc:  # noqa: BLE001
        eprint(f"[agentic-sdd gate] error: {exc}")
        return 1

    if p.stdout:
        sys.stdout.write(p.stdout)
    if p.stderr:
        sys.stderr.write(p.stderr)
    return p.returncode


if __name__ == "__main__":
    raise SystemExit(main())
