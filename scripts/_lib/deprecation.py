from __future__ import annotations

import sys
import warnings


def warn_deprecated(message: str) -> None:
    if not sys.stderr.isatty():
        return
    warnings.warn(message, DeprecationWarning, stacklevel=2)
