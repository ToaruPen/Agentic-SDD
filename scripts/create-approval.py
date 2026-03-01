#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/approval/create_approval.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

_new = Path(__file__).parent / "approval/create_approval.py"
if __name__ == "__main__":
    warnings.warn(
        "scripts/create-approval.py is deprecated. Use scripts/approval/create_approval.py instead.",
        DeprecationWarning,
        stacklevel=1,
    )
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
