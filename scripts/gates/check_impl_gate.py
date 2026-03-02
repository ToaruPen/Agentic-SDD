#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import json
from typing import Any

from _lib.git_utils import eprint, repo_root, run


def read_stdin_json() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return obj if isinstance(obj, dict) else {}


def extract_path(obj: dict[str, Any]) -> str | None:
    # Try common shapes used by tool hooks.
    candidates: list[Any] = []
    for key in ("tool_input", "input", "args", "parameters"):
        v = obj.get(key)
        if isinstance(v, dict):
            candidates.append(v)

    candidates.append(obj)

    for d in candidates:
        if not isinstance(d, dict):
            continue
        for k in ("path", "file", "file_path", "filePath", "filename", "target"):
            v = d.get(k)
            if isinstance(v, str) and v:
                return v
    return None


def is_agentic_sdd_local_path(path: str) -> bool:
    p = path.replace("\\", "/")
    return p == ".agentic-sdd" or p.startswith(".agentic-sdd/")


def main() -> int:
    obj = read_stdin_json()
    path = extract_path(obj)

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

    if path and is_agentic_sdd_local_path(path):
        # Allow writing Agentic-SDD local artifacts (approvals/reviews), but still enforce worktree.
        return 0

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
