#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/extract/resolve_sync_docs_inputs.py instead."""

import subprocess
import sys
import warnings
from pathlib import Path

warnings.warn(
    "scripts/resolve-sync-docs-inputs.py is deprecated. Use scripts/extract/resolve_sync_docs_inputs.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = Path(__file__).parent / "extract/resolve_sync_docs_inputs.py"
if __name__ == "__main__":
    sys.exit(
        subprocess.run(
            [sys.executable, str(_new), *sys.argv[1:]], check=False
        ).returncode
    )
