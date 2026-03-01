#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/gates/check_impl_gate.py instead."""

import os
import subprocess
import sys
import warnings

warnings.warn(
    "scripts/check-impl-gate.py is deprecated. Use scripts/gates/check_impl_gate.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = os.path.join(os.path.dirname(__file__), "gates/check_impl_gate.py")
if __name__ == "__main__":
    sys.exit(
        subprocess.run([sys.executable, _new, *sys.argv[1:]], check=False).returncode  # noqa: S603
    )
