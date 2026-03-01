#!/usr/bin/env python3

import os
import re
from urllib.parse import urlparse


def is_safe_repo_relative(path: str) -> bool:
    if not path:
        return False
    if path.startswith("/"):
        return False
    parts = [p for p in path.split("/") if p]
    if ".." in parts:
        return False
    return path not in {".", ".."}


def normalize_reference(ref: str) -> str:
    ref = ref.strip()

    # Markdown link: [text](target)
    m = re.search(r"\[[^\]]*\]\(([^)]+)\)", ref)
    if m:
        ref = m.group(1).strip()

    # Angle brackets (common in markdown autolinks)
    if ref.startswith("<") and ref.endswith(">"):
        ref = ref[1:-1].strip()

    # Backticks
    if ref.startswith("`") and ref.endswith("`"):
        ref = ref[1:-1].strip()

    # Strip fragment/query-ish tails
    return ref.split("#", 1)[0].strip()


def resolve_ref_to_repo_path(repo_root: str, ref: str) -> str:
    ref = normalize_reference(ref)
    if not ref:
        raise ValueError("empty reference")

    parsed = urlparse(ref)
    if parsed.scheme in {"http", "https"}:
        host = (parsed.hostname or "").lower()
        path = parsed.path or ""
        parts = [p for p in path.split("/") if p]

        # GitHub blob/tree URLs: /OWNER/REPO/blob/<ref>/path...
        if "blob" in parts:
            i = parts.index("blob")
            if len(parts) <= i + 2:
                raise ValueError(f"invalid GitHub blob URL: {ref}")
            rel = "/".join(parts[i + 2 :])
            if not is_safe_repo_relative(rel):
                raise ValueError(f"unsafe repo-relative path from URL: {ref}")
            return rel

        if "tree" in parts:
            i = parts.index("tree")
            if len(parts) <= i + 2:
                raise ValueError(f"invalid GitHub tree URL: {ref}")
            rel = "/".join(parts[i + 2 :])
            if not is_safe_repo_relative(rel):
                raise ValueError(f"unsafe repo-relative path from URL: {ref}")
            return rel

        # raw.githubusercontent.com/OWNER/REPO/<ref>/path...
        if host == "raw.githubusercontent.com":
            if len(parts) < 5:
                raise ValueError(f"invalid raw GitHub URL: {ref}")
            rel = "/".join(parts[4:])
            if not is_safe_repo_relative(rel):
                raise ValueError(f"unsafe repo-relative path from URL: {ref}")
            return rel

        raise ValueError(f"unsupported URL reference: {ref}")

    if os.path.isabs(ref):
        abs_path = os.path.realpath(ref)
        repo_abs = os.path.realpath(repo_root)
        if not abs_path.startswith(repo_abs + os.sep):
            raise ValueError(f"absolute path outside repo: {ref}")
        rel = os.path.relpath(abs_path, repo_abs)
        rel = rel.replace(os.sep, "/")
        if not is_safe_repo_relative(rel):
            raise ValueError(f"unsafe repo-relative path: {rel}")
        return rel

    rel = ref
    rel = rel.removeprefix("./")
    rel = rel.strip()
    rel = rel.replace("\\", "/")
    rel = os.path.normpath(rel).replace(os.sep, "/")
    if not is_safe_repo_relative(rel):
        raise ValueError(f"unsafe repo-relative path: {rel}")
    return rel


def find_issue_ref(body: str, key: str) -> str | None:
    # Matches: - Epic: ... / - PRD: ...
    pattern = re.compile(rf"^\s*[-*]\s*{re.escape(key)}\s*:\s*(.+?)\s*$", re.IGNORECASE)
    for line in body.splitlines():
        m = pattern.match(line)
        if not m:
            continue
        return m.group(1).strip()
    return None
