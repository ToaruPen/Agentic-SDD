#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/gates/validate_decision_index.py instead."""

import subprocess
import sys
from pathlib import Path

from _lib.deprecation import warn_deprecated
from _lib.subprocess_utils import exit_with_subprocess_returncode

_new = Path(__file__).parent / "gates/validate_decision_index.py"
if __name__ == "__main__":
    warn_deprecated(
        "scripts/validate-decision-index.py is deprecated. Use scripts/gates/validate_decision_index.py instead.",
    )
    exit_with_subprocess_returncode(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
