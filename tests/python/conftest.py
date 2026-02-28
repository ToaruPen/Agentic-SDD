"""Pytest configuration for Python tests.

Adds the scripts directory to sys.path so that modules like md_sanitize
can be imported when loading script modules via importlib.
"""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCRIPTS_DIR = str(_REPO_ROOT / "scripts")


def pytest_configure() -> None:
    """Add scripts directory to sys.path once for all tests."""
    if _SCRIPTS_DIR not in sys.path:
        sys.path.insert(0, _SCRIPTS_DIR)
