#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/generate/generate_project_config.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

warnings.warn(
    "scripts/generate-project-config.py is deprecated. Use scripts/generate/generate_project_config.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = Path(__file__).parent / "generate/generate_project_config.py"
if __name__ == "__main__":
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
