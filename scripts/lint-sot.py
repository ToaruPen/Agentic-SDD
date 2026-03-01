#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/lint/lint_sot.py instead."""

import os
import subprocess
import sys
import warnings

warnings.warn(
    "scripts/lint-sot.py is deprecated. Use scripts/lint/lint_sot.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = os.path.join(os.path.dirname(__file__), "lint/lint_sot.py")
if __name__ == "__main__":
    sys.exit(
        subprocess.run([sys.executable, _new, *sys.argv[1:]], check=False).returncode  # noqa: S603
    )
