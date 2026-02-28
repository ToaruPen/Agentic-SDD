#!/usr/bin/env python3
"""Validate Decision Snapshot index/body consistency.

Checks:
  AC1: Each decision body file contains all required template fields.
  AC2: Index entries and body files are 1:1 (no orphans, no dangling refs, no duplicates).
  AC3: Supersedes references point to existing Decision-IDs.

Usage:
  python3 scripts/validate-decision-index.py [<repo-root>]

Defaults to current working directory as repo root.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

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

# Pattern for index entries: "- <ID>: [`<path>`](<link>)"
INDEX_ENTRY_RE = re.compile(
    r"^-\s+(D-\d{4}-\d{2}-\d{2}-[A-Z][A-Z0-9_]*):\s+\[`([^`]+)`\]"
)


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def find_sections(text: str) -> set[str]:
    """Extract H2 section names from markdown text."""
    sections: set[str] = set()
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+)", line)
        if m:
            sections.add(m.group(1).strip())
    return sections


def extract_decision_id(text: str) -> str | None:
    """Extract the Decision-ID value from body text."""
    in_id_section = False
    for line in text.splitlines():
        if re.match(r"^##\s+Decision-ID", line):
            in_id_section = True
            continue
        if in_id_section:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                break
            m = DECISION_ID_RE.match(stripped)
            if m:
                return m.group(0)
    return None


def extract_supersedes(text: str) -> list[str]:
    """Extract Supersedes Decision-ID references from body text."""
    in_supersedes = False
    refs: list[str] = []
    for line in text.splitlines():
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
            m = DECISION_ID_RE.search(stripped)
            if m:
                refs.append(m.group(0))
    return refs


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
    for line in text.splitlines():
        if re.match(r"^##\s+Decision Index", line):
            in_index = True
            continue
        if in_index:
            if line.startswith("##"):
                break
            m = INDEX_ENTRY_RE.match(line.strip())
            if m:
                entries.append((m.group(1), m.group(2)))

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
    if decisions_dir.exists():
        for f in sorted(decisions_dir.iterdir()):
            if f.is_file() and f.name not in SKIP_FILES and f.suffix == ".md":
                body_files[f.name] = f

    # --- Collect all known Decision-IDs (from body files) ---
    all_decision_ids: dict[str, str] = {}  # id -> filename
    for fname, fpath in body_files.items():
        text = fpath.read_text(encoding="utf-8")
        did = extract_decision_id(text)
        if did:
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
        # ref_path is like "docs/decisions/d-2026-02-28-test.md"
        fname = Path(ref_path).name
        index_files.add(fname)
        if fname not in body_files:
            errors.append(
                f"Index references missing file: {ref_path} (Decision-ID: {did})"
            )

    # --- AC2: Check body -> index (orphan files) ---
    for fname in body_files:
        if fname not in index_files:
            errors.append(
                f"Body file not in index: docs/decisions/{fname} "
                f"— add it to docs/decisions.md ## Decision Index"
            )

    # --- AC1: Check required sections in each body file ---
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
        supersedes_refs = extract_supersedes(text)
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
