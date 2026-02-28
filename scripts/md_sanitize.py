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
    for line in text.splitlines(keepends=True):
        if _INDENTED_CODE_RE.match(line):
            continue
        out_lines.append(line)
    return "".join(out_lines)


def _mask_inline_code_spans(text: str) -> str:
    """Replace inline code spans with spaces, preserving string length.

    Follows CommonMark rules:
    - ``\\``` outside a code span is an escaped backtick (not a delimiter).
    - Inside code spans, backslash is literal (no escaping).
    - Code spans are opened/closed by backtick strings of equal length.
    """
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        # --- backslash sequences (outside code spans) ---
        if text[i] == "\\":
            bs_start = i
            while i < n and text[i] == "\\":
                i += 1
            num_bs = i - bs_start
            # Odd backslashes followed by backtick → last \` is escaped
            if i < n and text[i] == "`" and num_bs % 2 == 1:
                i += 1  # skip the escaped backtick
            continue
        # --- potential code span opener ---
        if text[i] == "`":
            open_start = i
            while i < n and text[i] == "`":
                i += 1
            open_len = i - open_start
            # search for matching closer (no escaping inside code spans)
            k = i
            while k < n:
                if text[k] == "`":
                    cs = k
                    while k < n and text[k] == "`":
                        k += 1
                    if k - cs == open_len:
                        for p in range(open_start, k):
                            out[p] = " "
                        i = k
                        break
                else:
                    k += 1
            # if not found, i is already past the opening backticks
        else:
            i += 1
    return "".join(out)


def strip_html_comment_blocks(text: str) -> str:
    """Strip HTML comment blocks from markdown text.

    Inline code spans are masked first (using a CommonMark-compliant
    parser that correctly handles escaped backticks) so that ``<!--``
    / ``-->`` inside real code spans are never treated as comment
    delimiters.  Matched ``<!-- ... -->`` pairs (outside inline code)
    are then removed from the **original** text.  For a genuine
    unmatched ``<!--`` (no closing ``-->`` and not inside inline code),
    everything from that opener onward is removed.
    """
    masked = _mask_inline_code_spans(text)
    # Find matched <!-- ... --> spans in the masked copy, then splice
    # the *original* text around those ranges to preserve inline code.
    parts: List[str] = []
    last_end = 0
    for m in _HTML_COMMENT_BLOCK_RE.finditer(masked):
        parts.append(text[last_end : m.start()])
        last_end = m.end()
    parts.append(text[last_end:])
    result = "".join(parts)
    # Check for a genuine unmatched <!-- (re-mask since character
    # positions shifted after comment removal).
    result_masked = _mask_inline_code_spans(result)
    i = result_masked.find("<!--")
    if i == -1:
        return result
    return result[:i]


def sanitize_status_text(text: str) -> str:
    """Strip fenced code blocks, indented code blocks, and HTML comments.

    This is the standard pipeline for extracting status metadata from
    Markdown documents.  Centralised here to avoid duplicating the call
    chain in every consumer.
    """
    return strip_html_comment_blocks(
        strip_indented_code_blocks(strip_fenced_code_blocks(text))
    )
