#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/gates/validate_decision_index.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

_new = Path(__file__).parent / "gates/validate_decision_index.py"
if __name__ == "__main__":
    warnings.warn(
        "scripts/validate-decision-index.py is deprecated. Use scripts/gates/validate_decision_index.py instead.",
        DeprecationWarning,
        stacklevel=1,
    )
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
