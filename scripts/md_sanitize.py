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

# Regex to match Markdown escaped backticks (\`).
# Handles even-numbered backslash pairs (\\) that precede the escaped backtick
# so that \\` (escaped backslash + real backtick) is NOT neutralized.
_ESCAPED_BACKTICK_RE = re.compile(r"(?<!\\)((?:\\\\)*)\\`")


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


def _neutralize_escaped_backticks(text: str) -> str:
    """Replace Markdown escaped backticks (``\\````) with spaces.

    Preserves string length so character positions remain aligned.
    Even-numbered backslash pairs (``\\\\``) before the escaped backtick
    are kept; only the final ``\\``` is replaced with two spaces.
    """
    return _ESCAPED_BACKTICK_RE.sub(lambda m: m.group(1) + "  ", text)


def strip_html_comment_blocks(text: str) -> str:
    """Strip HTML comment blocks from markdown text.

    Escaped backticks (``\\````) are neutralized first so they are not
    treated as code span delimiters.  Then inline code spans are masked
    so that ``<!--`` / ``-->`` inside real backticks are never treated as
    comment delimiters.  Matched ``<!-- ... -->`` pairs (outside inline
    code) are then removed from the **original** text.  For a genuine
    unmatched ``<!--`` (no closing ``-->`` and not inside inline code),
    everything from that opener onward is removed.
    """
    # Neutralize escaped backticks, then mask inline code spans.
    neutralized = _neutralize_escaped_backticks(text)
    masked = _INLINE_CODE_RE.sub(lambda m: " " * len(m.group()), neutralized)
    # Find matched <!-- ... --> spans in the masked copy, then splice
    # the *original* text around those ranges to preserve inline code.
    parts: List[str] = []
    last_end = 0
    for m in _HTML_COMMENT_BLOCK_RE.finditer(masked):
        parts.append(text[last_end : m.start()])
        last_end = m.end()
    parts.append(text[last_end:])
    result = "".join(parts)
    # Check for a genuine unmatched <!-- (re-neutralize + re-mask since
    # character positions shifted after comment removal).
    result_neutralized = _neutralize_escaped_backticks(result)
    result_masked = _INLINE_CODE_RE.sub(
        lambda m: " " * len(m.group()), result_neutralized
    )
    i = result_masked.find("<!--")
    if i == -1:
        return result
    return result[:i]
