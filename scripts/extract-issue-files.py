#!/usr/bin/env python3
"""Backward-compat wrapper. Use scripts/extract/extract_issue_files.py instead."""

import os
import subprocess
import sys
import warnings

warnings.warn(
    "scripts/extract-issue-files.py is deprecated. Use scripts/extract/extract_issue_files.py instead.",
    DeprecationWarning,
    stacklevel=1,
)

_new = os.path.join(os.path.dirname(__file__), "extract/extract_issue_files.py")
if __name__ == "__main__":
    sys.exit(
        subprocess.run([sys.executable, _new, *sys.argv[1:]], check=False).returncode  # noqa: S603
    )
