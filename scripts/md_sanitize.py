"""Backward-compat wrapper. Use scripts/_lib/md_sanitize.py instead."""

import warnings

from _lib.md_sanitize import (  # noqa: F401
    sanitize_status_text,
    strip_fenced_code_blocks,
    strip_html_comment_blocks,
    strip_indented_code_blocks,
)

warnings.warn(
    "scripts/md_sanitize.py is deprecated. Use scripts/_lib/md_sanitize.py instead.",
    DeprecationWarning,
    stacklevel=1,
)
