#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/gates/check_impl_gate.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

_new = Path(__file__).parent / "gates/check_impl_gate.py"
if __name__ == "__main__":
    warnings.warn(
        "scripts/check-impl-gate.py is deprecated. Use scripts/gates/check_impl_gate.py instead.",
        DeprecationWarning,
        stacklevel=1,
    )
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
