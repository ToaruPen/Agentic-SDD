#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import json
import subprocess
from pathlib import Path
from typing import Any

from _lib.subprocess_utils import run_cmd


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: list[str],
    cwd: str | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return run_cmd(cmd, cwd=cwd, check=check)


def repo_root() -> str | None:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=False)
    except OSError:
        return None
    root = (p.stdout or "").strip()
    if not root:
        return None
    return str(Path(root).resolve())


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
    if p == ".agentic-sdd" or p.startswith(".agentic-sdd/"):
        return True
    return "/.agentic-sdd/" in p


def main() -> int:
    obj = read_stdin_json()
    path = extract_path(obj)

    root = repo_root()
    if not root:
        return 0

    worktree_gate = Path(root) / "scripts" / "validate-worktree.py"
    if worktree_gate.is_file():
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

    script = Path(root) / "scripts" / "validate-approval.py"
    if not script.is_file():
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
