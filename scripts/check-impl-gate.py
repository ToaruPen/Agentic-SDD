#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from typing import Any, Dict, List, Optional


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


def read_stdin_json() -> Dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return obj if isinstance(obj, dict) else {}


def extract_path(obj: Dict[str, Any]) -> Optional[str]:
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
    if "/.agentic-sdd/" in p:
        return True
    return False


def main() -> int:
    obj = read_stdin_json()
    path = extract_path(obj)

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

    if path and is_agentic_sdd_local_path(path):
        # Allow writing Agentic-SDD local artifacts (approvals/reviews), but still enforce worktree.
        return 0

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
