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
    in_code = False
    for line in text.splitlines(keepends=True):
        if _INDENTED_CODE_RE.match(line):
            in_code = True
            continue

        if in_code:
            in_code = False

        out_lines.append(line)
    return "".join(out_lines)


def strip_html_comment_blocks(text: str) -> str:
    """Strip HTML comment blocks from markdown text."""
    out = _HTML_COMMENT_BLOCK_RE.sub("", text)
    i = out.find("<!--")
    if i == -1:
        return out
    return out[:i]
