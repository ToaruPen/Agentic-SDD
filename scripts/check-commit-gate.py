#!/usr/bin/env python3

import os
import sys
from typing import List, Optional

import subprocess


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: List[str],
    cwd: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
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


def main() -> int:
    root = repo_root()
    if not root:
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
