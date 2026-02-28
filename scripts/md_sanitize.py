#!/usr/bin/env python3
"""
Markdown sanitization utilities for stripping code blocks and comments.
"""

import re
from typing import List

# Regex patterns for fenced code blocks (``` or ~~~)
_FENCE_OPEN_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))")
_FENCE_CLOSE_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))[ \t]*$")

# Regex pattern for indented code blocks (tab or 4+ spaces)
_INDENTED_CODE_RE = re.compile(r"^(?:\t| {4,})")

# Regex pattern for HTML comment blocks
_HTML_COMMENT_BLOCK_RE = re.compile(r"<!--.*?-->", re.DOTALL)

# Regex pattern for inline code spans (backtick sequences)
_INLINE_CODE_RE = re.compile(r"(`+)(.+?)\1", re.DOTALL)


def strip_fenced_code_blocks(text: str) -> str:
    """Strip fenced code blocks (``` or ~~~) from markdown text."""
    out_lines: List[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0

    for line in text.splitlines(keepends=True):
        if not in_fence:
            m_open = _FENCE_OPEN_RE.match(line)
            if m_open:
                seq = m_open.group(1)
                in_fence = True
                fence_char = seq[0]
                fence_len = len(seq)
                continue
        else:
            m_close = _FENCE_CLOSE_RE.match(line)
            if m_close:
                seq = m_close.group(1)
                if seq[0] == fence_char and len(seq) >= fence_len:
                    in_fence = False
                    fence_char = ""
                    fence_len = 0
                    continue

        if not in_fence:
            out_lines.append(line)

    return "".join(out_lines)


def strip_indented_code_blocks(text: str) -> str:
    """Strip indented code blocks (tab or 4+ spaces) from markdown text."""
    out_lines: List[str] = []
    for line in text.splitlines(keepends=True):
        if _INDENTED_CODE_RE.match(line):
            continue
        out_lines.append(line)
    return "".join(out_lines)


def strip_html_comment_blocks(text: str) -> str:
    """Strip HTML comment blocks from markdown text.

    Inline code spans are masked first so that ``<!--`` / ``-->`` inside
    backticks are never treated as comment delimiters.  Matched
    ``<!-- ... -->`` pairs (outside inline code) are then removed from
    the **original** text.  For a genuine unmatched ``<!--`` (no closing
    ``-->`` and not inside inline code), everything from that opener
    onward is removed.
    """
    # Mask inline code spans to find real comment boundaries without
    # treating `<!--`/`-->` inside backticks as delimiters.
    masked = _INLINE_CODE_RE.sub(lambda m: " " * len(m.group()), text)
    # Find matched <!-- ... --> spans in the masked copy, then splice
    # the *original* text around those ranges to preserve inline code.
    parts: List[str] = []
    last_end = 0
    for m in _HTML_COMMENT_BLOCK_RE.finditer(masked):
        parts.append(text[last_end : m.start()])
        last_end = m.end()
    parts.append(text[last_end:])
    result = "".join(parts)
    # Check for a genuine unmatched <!-- (re-mask inline code since
    # character positions shifted after comment removal).
    result_masked = _INLINE_CODE_RE.sub(lambda m: " " * len(m.group()), result)
    i = result_masked.find("<!--")
    if i == -1:
        return result
    return result[:i]
