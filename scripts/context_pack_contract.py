#!/usr/bin/env python3

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ContextPackContract:
    header: str
    keys: tuple[str, ...]
    line_count: int
    forbidden_markers: tuple[str, ...]


def _extract_key(line: str) -> str:
    m = re.match(r"^([a-z_]+:)", line.strip())
    if not m:
        raise ValueError(f"invalid Context Pack key line: {line}")
    return m.group(1)


def _extract_line_count(docs_text: str) -> int:
    m = re.search(r"exactly\s+([0-9]+)\s+lines\s+total", docs_text)
    if not m:
        raise ValueError("missing line-count rule in docs agent contract")
    return int(m.group(1))


def _require_policy_markers(docs_text: str) -> None:
    required = (
        "Do not output code fences",
        "YAML frontmatter separators (---)",
        "Evidence pointer format: a single repo-relative FILE path only.",
    )
    for marker in required:
        if marker not in docs_text:
            raise ValueError(
                f"missing required policy marker in docs contract: {marker}"
            )


def load_context_pack_contract(repo_root: Path) -> ContextPackContract:
    docs_path = repo_root / ".agent/agents/docs.md"
    docs_text = docs_path.read_text(encoding="utf-8")
    lines = docs_text.splitlines()

    header = "[Context Pack v1]"
    try:
        header_index = next(i for i, line in enumerate(lines) if line.strip() == header)
    except StopIteration as exc:
        raise ValueError(
            "missing Context Pack template header in docs agent contract"
        ) from exc

    keys = []
    for raw in lines[header_index + 1 :]:
        line = raw.strip()
        if not line:
            break
        keys.append(_extract_key(line))

    line_count = _extract_line_count(docs_text)
    if line_count != len(keys) + 1:
        raise ValueError(
            "line-count rule does not match template lines: "
            f"line_count={line_count}, template_lines={len(keys) + 1}"
        )

    _require_policy_markers(docs_text)

    return ContextPackContract(
        header=header,
        keys=tuple(keys),
        line_count=line_count,
        forbidden_markers=("```", "---"),
    )
