import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from _lib.approval_constants import MODE_ALLOWED, MODE_SOURCE_ALLOWED

__all__ = ["MODE_ALLOWED", "MODE_SOURCE_ALLOWED"]
