#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/lint/assemble_sot.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

_new = Path(__file__).parent / "lint/assemble_sot.py"
if __name__ == "__main__":
    warnings.warn(
        "scripts/assemble-sot.py is deprecated. Use scripts/lint/assemble_sot.py instead.",
        DeprecationWarning,
        stacklevel=1,
    )
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
