import re

_FENCE_OPEN_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))")
_FENCE_CLOSE_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))[ \t]*$")
_INDENTED_CODE_RE = re.compile(r"^(?:\t| {4,})")
_HTML_COMMENT_BLOCK_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def strip_fenced_code_blocks(text: str) -> str:
    out_lines: list[str] = []
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
    out_lines: list[str] = []
    for line in text.splitlines(keepends=True):
        if _INDENTED_CODE_RE.match(line):
            continue
        out_lines.append(line)
    return "".join(out_lines)


def _mask_inline_code_spans(text: str) -> str:
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "\\":
            bs_start = i
            while i < n and text[i] == "\\":
                i += 1
            num_bs = i - bs_start
            if i < n and text[i] == "`" and num_bs % 2 == 1:
                i += 1
            continue
        if text[i] == "`":
            open_start = i
            while i < n and text[i] == "`":
                i += 1
            open_len = i - open_start
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
        else:
            i += 1
    return "".join(out)


def strip_html_comment_blocks(text: str) -> str:
    masked = _mask_inline_code_spans(text)
    parts: list[str] = []
    last_end = 0
    for m in _HTML_COMMENT_BLOCK_RE.finditer(masked):
        parts.append(text[last_end : m.start()])
        last_end = m.end()
    parts.append(text[last_end:])
    result = "".join(parts)
    result_masked = _mask_inline_code_spans(result)
    i = result_masked.find("<!--")
    if i == -1:
        return result
    return result[:i]


def sanitize_status_text(text: str) -> str:
    return strip_html_comment_blocks(
        strip_indented_code_blocks(strip_fenced_code_blocks(text))
    )
