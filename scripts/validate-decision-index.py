#!/usr/bin/env python3
"""Validate Decision Snapshot index/body consistency.

Checks:
  AC1: docs/decisions/_template.md contains all required fields.
  AC2: Index entries and body files are 1:1 (no orphans, no dangling refs, no duplicates).
  AC3: Supersedes references point to existing Decision-IDs.

Usage:
  python3 scripts/validate-decision-index.py [<repo-root>]

Defaults to current working directory as repo root.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path, PurePosixPath

# Required sections in every decision body (from _template.md / README.md)
REQUIRED_SECTIONS: list[str] = [
    "Decision-ID",
    "Context",
    "Rationale",
    "Alternatives",
    "Impact",
    "Verification",
    "Supersedes",
    "Inputs Fingerprint",
]

# Files to skip in the decisions directory
SKIP_FILES: set[str] = {"_template.md", "README.md"}

# Pattern matching Decision-ID values (D-YYYY-MM-DD-UPPER_SNAKE)
DECISION_ID_RE = re.compile(r"D-\d{4}-\d{2}-\d{2}-[A-Z][A-Z0-9_]*")

INDEX_ENTRY_RE = re.compile(
    r"^-\s+(D-\d{4}-\d{2}-\d{2}-[A-Z][A-Z0-9_]*):\s+\[`([^`]+)`\]\(([^)]+)\)\s*$"
)


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def iter_non_fenced_lines(text: str) -> list[str]:
    lines: list[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0

    for line in text.splitlines():
        fence_match = re.match(r"^\s*([`~]{3,})", line)
        if fence_match:
            marker = fence_match.group(1)
            marker_char = marker[0]
            marker_len = len(marker)

            if not in_fence:
                in_fence = True
                fence_char = marker_char
                fence_len = marker_len
                continue

            if marker_char == fence_char and marker_len >= fence_len:
                in_fence = False
                continue

        if in_fence:
            continue

        lines.append(line)

    return lines


def find_sections(text: str) -> set[str]:
    """Extract H2 section names from markdown text."""
    sections: set[str] = set()
    for line in iter_non_fenced_lines(text):
        m = re.match(r"^##\s+(.+)", line)
        if m:
            sections.add(m.group(1).strip())
    return sections


def extract_decision_id(text: str) -> str | None:
    """Extract the Decision-ID value from body text."""
    in_id_section = False
    for line in iter_non_fenced_lines(text):
        if re.match(r"^##\s+Decision-ID", line):
            in_id_section = True
            continue
        if in_id_section:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                break
            if DECISION_ID_RE.fullmatch(stripped):
                return stripped
    return None


def extract_supersedes(text: str) -> tuple[list[str], list[str]]:
    """Extract Supersedes Decision-ID references and invalid entries from body text."""
    in_supersedes = False
    refs: list[str] = []
    invalid_entries: list[str] = []
    for line in iter_non_fenced_lines(text):
        if re.match(r"^##\s+Supersedes", line):
            in_supersedes = True
            continue
        if in_supersedes:
            stripped = line.strip()
            if stripped.startswith("#"):
                break
            if not stripped:
                continue
            # Skip N/A
            if stripped in ("- N/A", "N/A"):
                continue
            payload = stripped
            if payload.startswith("-"):
                payload = payload[1:].strip()

            tokens = [token.strip() for token in payload.split(",") if token.strip()]
            if not tokens:
                invalid_entries.append(stripped)
                continue

            if all(DECISION_ID_RE.fullmatch(token) for token in tokens):
                refs.extend(tokens)
            else:
                invalid_entries.append(stripped)
    return refs, invalid_entries


def parse_index(index_path: Path) -> tuple[list[tuple[str, str]], list[str]]:
    """Parse decisions.md and return (entries, errors).

    entries: list of (decision_id, referenced_file_path)
    errors: list of error messages
    """
    entries: list[tuple[str, str]] = []
    errors: list[str] = []

    if not index_path.exists():
        errors.append(f"Index file not found: {index_path}")
        return entries, errors

    text = index_path.read_text(encoding="utf-8")
    in_index = False
    found_index_header = False
    in_html_comment = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        if re.match(r"^##\s+Decision Index", line):
            in_index = True
            found_index_header = True
            continue
        if in_index:
            if re.match(r"^##(?!#)\s+", line):
                break
            if re.match(r"^#{3,}\s+", line):
                continue
            stripped = line.strip()
            if in_html_comment:
                if "-->" in stripped:
                    in_html_comment = False
                continue

            if stripped.startswith("<!--"):
                if "-->" not in stripped:
                    in_html_comment = True
                continue

            if not stripped:
                continue

            m = INDEX_ENTRY_RE.match(stripped)
            if m:
                entries.append((m.group(1), m.group(3)))
            else:
                errors.append(
                    f"Invalid Decision Index line at {index_path}:{lineno}: {stripped}"
                )

    if not found_index_header:
        errors.append(f"Missing section '## Decision Index' in {index_path}")

    return entries, errors


def validate(repo_root: Path) -> list[str]:
    """Run all validation checks and return a list of error messages."""
    errors: list[str] = []

    decisions_dir = repo_root / "docs" / "decisions"
    index_path = repo_root / "docs" / "decisions.md"

    # --- Parse index ---
    index_entries, parse_errors = parse_index(index_path)
    errors.extend(parse_errors)
    if parse_errors:
        return errors

    # --- Collect body files ---
    body_files: dict[str, Path] = {}
    body_repo_paths: dict[str, Path] = {}
    if decisions_dir.exists():
        for f in sorted(decisions_dir.iterdir()):
            if f.is_file() and f.name not in SKIP_FILES and f.suffix == ".md":
                body_files[f.name] = f
                body_repo_paths[f"docs/decisions/{f.name}"] = f

    template_path = decisions_dir / "_template.md"
    if not template_path.exists():
        errors.append(
            "docs/decisions/_template.md: missing template file "
            "(required for AC1 validation)"
        )
    else:
        template_sections = find_sections(template_path.read_text(encoding="utf-8"))
        for req in REQUIRED_SECTIONS:
            if req not in template_sections:
                errors.append(
                    f"docs/decisions/_template.md: missing required section '## {req}'"
                )

    # --- Collect all known Decision-IDs (from body files) ---
    body_decision_ids: dict[str, str] = {}
    all_decision_ids: dict[str, str] = {}
    for fname, fpath in body_files.items():
        text = fpath.read_text(encoding="utf-8")
        did = extract_decision_id(text)
        if not did:
            errors.append(
                f"docs/decisions/{fname}: missing or invalid Decision-ID value "
                f"(expected format: D-YYYY-MM-DD-UPPER_SNAKE)"
            )
            continue

        body_decision_ids[fname] = did

        if did in all_decision_ids:
            errors.append(
                f"Duplicate Decision-ID in body files: {did} "
                f"(docs/decisions/{all_decision_ids[did]} and docs/decisions/{fname})"
            )
            continue

        all_decision_ids[did] = fname

    # --- AC2: Check for duplicates in index ---
    seen_ids: dict[str, int] = {}
    for did, _ in index_entries:
        seen_ids[did] = seen_ids.get(did, 0) + 1
    for did, count in seen_ids.items():
        if count > 1:
            errors.append(
                f"Duplicate index entry: {did} (appears {count} times / 重複)"
            )

    # --- AC2: Check index -> body (dangling references) ---
    index_files: set[str] = set()
    for did, ref_path in index_entries:
        if ref_path.startswith("./"):
            repo_rel_raw = f"docs/{ref_path[2:]}"
        else:
            errors.append(
                f"Invalid index link path: {ref_path} (Decision-ID: {did}) "
                f"— must start with './decisions/'"
            )
            continue

        repo_rel = PurePosixPath(repo_rel_raw)
        if ".." in repo_rel.parts:
            errors.append(
                f"Invalid index link path traversal: {ref_path} (Decision-ID: {did})"
            )
            continue

        if len(repo_rel.parts) < 3 or repo_rel.parts[0:2] != ("docs", "decisions"):
            errors.append(
                f"Index link must point to docs/decisions/*.md: {ref_path} "
                f"(Decision-ID: {did})"
            )
            continue

        resolved_repo_rel = str(PurePosixPath(*repo_rel.parts))
        resolved_path = repo_root.joinpath(*repo_rel.parts)
        index_files.add(resolved_repo_rel)

        if not resolved_path.exists():
            errors.append(
                f"Index references missing file: {ref_path} (Decision-ID: {did})"
            )
            continue

        if resolved_repo_rel not in body_repo_paths:
            errors.append(
                f"Index references unmanaged file: {ref_path} (Decision-ID: {did})"
            )
            continue

        fname = body_repo_paths[resolved_repo_rel].name
        body_did = body_decision_ids.get(fname)
        if body_did and body_did != did:
            errors.append(
                f"Index/body Decision-ID mismatch: index has '{did}' but "
                f"docs/decisions/{fname} has '{body_did}'"
            )

    # --- AC2: Check body -> index (orphan files) ---
    for body_repo_rel in body_repo_paths:
        if body_repo_rel not in index_files:
            fname = Path(body_repo_rel).name
            errors.append(
                f"Body file not in index: docs/decisions/{fname} "
                f"— add it to docs/decisions.md ## Decision Index"
            )

    for fname, fpath in body_files.items():
        text = fpath.read_text(encoding="utf-8")
        sections = find_sections(text)
        for req in REQUIRED_SECTIONS:
            if req not in sections:
                errors.append(
                    f"docs/decisions/{fname}: missing required section '## {req}' "
                    f"(Rationale etc. — see _template.md)"
                )

    # --- AC3: Check Supersedes references ---
    for fname, fpath in body_files.items():
        text = fpath.read_text(encoding="utf-8")
        supersedes_refs, invalid_supersedes_entries = extract_supersedes(text)
        for invalid_entry in invalid_supersedes_entries:
            errors.append(
                f"docs/decisions/{fname}: invalid Supersedes entry '{invalid_entry}'. "
                f"修正指針: D-YYYY-MM-DD-UPPER_SNAKE 形式のDecision-IDを指定してください。"
            )

        for ref_id in supersedes_refs:
            if ref_id not in all_decision_ids:
                errors.append(
                    f"docs/decisions/{fname}: Supersedes references non-existent "
                    f"Decision-ID '{ref_id}'. "
                    f"修正指針: Supersedes先のDecision-IDが正しいか確認し、"
                    f"該当ファイルが docs/decisions/ に存在することを確認してください。"
                )

    return errors


def main() -> None:
    if len(sys.argv) > 1:
        repo_root = Path(sys.argv[1])
    else:
        repo_root = Path.cwd()

    errors = validate(repo_root)
    if errors:
        for err in errors:
            eprint(f"ERROR: {err}")
        sys.exit(1)
    else:
        print("Decision index validation: OK")


if __name__ == "__main__":
    main()
