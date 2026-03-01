#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/lint/bench_sdd_docs.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

warnings.warn(
    "scripts/bench-sdd-docs.py is deprecated. Use scripts/lint/bench_sdd_docs.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = Path(__file__).parent / "lint/bench_sdd_docs.py"
if __name__ == "__main__":
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
