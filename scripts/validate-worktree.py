#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/gates/validate_worktree.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

warnings.warn(
    "scripts/validate-worktree.py is deprecated. Use scripts/gates/validate_worktree.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = Path(__file__).parent / "gates/validate_worktree.py"
if __name__ == "__main__":
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
