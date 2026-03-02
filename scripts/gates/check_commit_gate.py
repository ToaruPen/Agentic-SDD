#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import json
import shlex

from _lib.git_utils import eprint, repo_root, run


def should_check_command(command: str) -> bool:
    """Check if the command is a git commit or git push command."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if not tokens:
        return False

    git_index = -1
    for i, part in enumerate(tokens):
        if Path(part).name == "git":
            git_index = i
            break
    if git_index < 0:
        return False

    value_opts = {
        "-c",
        "-C",
        "--git-dir",
        "--work-tree",
        "--namespace",
        "--super-prefix",
        "--exec-path",
        "--config-env",
    }

    i = git_index + 1
    while i < len(tokens):
        part = tokens[i]
        if part == "--":
            i += 1
            break
        if not part.startswith("-"):
            return part in {"commit", "push"}
        if part in value_opts and i + 1 < len(tokens):
            i += 2
            continue
        i += 1

    if i < len(tokens):
        return tokens[i] in {"commit", "push"}
    return False


def main() -> int:
    # Read hook input from stdin
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        eprint(f"[agentic-sdd gate] error: invalid hook payload: {exc}")
        return 1

    if not isinstance(input_data, dict):
        eprint("[agentic-sdd gate] error: hook payload is not a JSON object")
        return 1
    tool_input = input_data.get("tool_input", {})
    if not isinstance(tool_input, dict):
        eprint("[agentic-sdd gate] error: tool_input is not a JSON object")
        return 1
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        command = ""

    # Only check git commit/push commands
    if not should_check_command(command):
        return 0
    root = repo_root()
    if not root:
        return 0

    worktree_gate = None
    for rel in (
        Path("scripts", "gates", "validate_worktree.py"),
        Path("scripts", "validate-worktree.py"),
    ):
        candidate = Path(root) / rel
        if candidate.is_file():
            worktree_gate = candidate
            break
    if worktree_gate is not None:
        try:
            p = run([sys.executable, str(worktree_gate)], cwd=root, check=False)
        except OSError as exc:
            eprint(f"[agentic-sdd gate] error: {exc}")
            return 1
        if p.stdout:
            sys.stdout.write(p.stdout)
        if p.stderr:
            sys.stderr.write(p.stderr)
        if p.returncode != 0:
            return p.returncode

    script = None
    for rel in (
        Path("scripts", "gates", "validate_approval.py"),
        Path("scripts", "validate-approval.py"),
    ):
        candidate = Path(root) / rel
        if candidate.is_file():
            script = candidate
            break
    if script is None:
        return 0

    try:
        p = run([sys.executable, str(script)], cwd=root, check=False)

    except OSError as exc:
        eprint(f"[agentic-sdd gate] error: {exc}")
        return 1

    if p.stdout:
        sys.stdout.write(p.stdout)
    if p.stderr:
        sys.stderr.write(p.stderr)
    return p.returncode


if __name__ == "__main__":
    raise SystemExit(main())
