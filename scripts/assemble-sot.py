#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def is_safe_repo_relative(path: str) -> bool:
    if not path:
        return False
    if path.startswith("/"):
        return False
    parts = [p for p in path.split("/") if p]
    if ".." in parts:
        return False
    if path in {".", ".."}:
        return False
    return True


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
    ref = ref.split("#", 1)[0].strip()
    return ref


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
    if rel.startswith("./"):
        rel = rel[2:]
    rel = rel.strip()
    rel = rel.replace("\\", "/")
    rel = os.path.normpath(rel).replace(os.sep, "/")
    if not is_safe_repo_relative(rel):
        raise ValueError(f"unsafe repo-relative path: {rel}")
    return rel


def find_issue_ref(body: str, key: str) -> Optional[str]:
    # Matches: - Epic: ... / - PRD: ...
    pattern = re.compile(rf"^\s*[-*]\s*{re.escape(key)}\s*:\s*(.+?)\s*$", re.IGNORECASE)
    for line in body.splitlines():
        m = pattern.match(line)
        if not m:
            continue
        val = m.group(1).strip()
        return val
    return None


def split_level2_sections(text: str) -> Tuple[str, List[Tuple[str, str]]]:
    lines = text.splitlines(keepends=True)
    pre: List[str] = []
    sections: List[Tuple[str, str]] = []

    current_title: Optional[str] = None
    current_body: List[str] = []

    def flush() -> None:
        nonlocal current_title, current_body
        if current_title is None:
            return
        sections.append((current_title, "".join(current_body)))
        current_title = None
        current_body = []

    for line in lines:
        if line.startswith("## "):
            flush()
            current_title = line.rstrip("\n")
            current_body = [line]
            continue
        if current_title is None:
            pre.append(line)
        else:
            current_body.append(line)

    flush()
    return "".join(pre), sections


def extract_wide_markdown(text: str) -> str:
    pre, sections = split_level2_sections(text)
    out: List[str] = []

    if pre.strip():
        out.append(pre.rstrip() + "\n\n")

    for i, (title, body) in enumerate(sections):
        # Include first section (usually metadata) + numbered sections 1-8.
        if i == 0:
            out.append(body.rstrip() + "\n\n")
            continue
        if re.match(r"^##\s+[1-8]\.", title):
            out.append(body.rstrip() + "\n\n")

    return "".join(out).rstrip() + "\n"


def read_issue_json(path: str) -> Dict[str, str]:
    raw = read_text(path)
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("issue json must be an object")
    title = str(data.get("title") or "")
    url = str(data.get("url") or "")
    body = str(data.get("body") or "")
    number = data.get("number")
    num_s = str(number) if isinstance(number, int) else ""
    return {"title": title, "url": url, "body": body, "number": num_s}


def build_sot(
    repo_root: str,
    issue: Optional[Dict[str, str]],
    manual_sot: str,
    extra_files: List[str],
    max_chars: int,
) -> str:
    blocks: List[str] = []

    if issue is not None:
        blocks.append("== Issue ==\n")
        if issue.get("number"):
            blocks.append(f"Number: {issue['number']}\n")
        if issue.get("url"):
            blocks.append(f"URL: {issue['url']}\n")
        if issue.get("title"):
            blocks.append(f"Title: {issue['title']}\n")
        blocks.append("\n")
        blocks.append(issue.get("body", "").rstrip() + "\n\n")

        prd_ref = find_issue_ref(issue.get("body", ""), "PRD")
        epic_ref = find_issue_ref(issue.get("body", ""), "Epic")

        # Fail-fast when the reference line exists but cannot be resolved.
        if prd_ref is not None:
            prd_ref = prd_ref.strip()
            if not prd_ref or "<!--" in prd_ref:
                raise ValueError(
                    f"PRD reference present but empty/placeholder: {prd_ref}"
                )

            prd_path = resolve_ref_to_repo_path(repo_root, prd_ref)
            abs_prd = os.path.join(repo_root, prd_path)
            if not os.path.isfile(abs_prd):
                raise FileNotFoundError(
                    f"PRD file not found: {prd_path} (from: {prd_ref})"
                )
            prd_text = read_text(abs_prd)
            blocks.append("== PRD (wide excerpt) ==\n")
            blocks.append(f"Path: {prd_path}\n\n")
            blocks.append(extract_wide_markdown(prd_text) + "\n")

        if epic_ref is not None:
            epic_ref = epic_ref.strip()
            if not epic_ref or "<!--" in epic_ref:
                raise ValueError(
                    f"Epic reference present but empty/placeholder: {epic_ref}"
                )

            epic_path = resolve_ref_to_repo_path(repo_root, epic_ref)
            abs_epic = os.path.join(repo_root, epic_path)
            if not os.path.isfile(abs_epic):
                raise FileNotFoundError(
                    f"Epic file not found: {epic_path} (from: {epic_ref})"
                )
            epic_text = read_text(abs_epic)
            blocks.append("== Epic (wide excerpt) ==\n")
            blocks.append(f"Path: {epic_path}\n\n")
            blocks.append(extract_wide_markdown(epic_text) + "\n")

    for rel in extra_files:
        abs_path = os.path.join(repo_root, rel)
        if not os.path.isfile(abs_path):
            raise FileNotFoundError(f"SoT file not found: {rel}")
        blocks.append("== Extra SoT File ==\n")
        blocks.append(f"Path: {rel}\n\n")
        blocks.append(read_text(abs_path).rstrip() + "\n\n")

    if manual_sot.strip():
        blocks.append("== Manual SoT ==\n")
        blocks.append(manual_sot.rstrip() + "\n")

    out = "".join(blocks).rstrip() + "\n"
    if max_chars > 0 and len(out) > max_chars:
        out = out[:max_chars].rstrip() + "\n\n[TRUNCATED]\n"
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Assemble SoT bundle for review-cycle."
    )
    parser.add_argument("--repo-root", required=True, help="Repo root")
    parser.add_argument(
        "--issue-json", default="", help="Path to gh issue view --json output"
    )
    parser.add_argument(
        "--issue-body-file", default="", help="Path to file containing issue body"
    )
    parser.add_argument("--manual-sot", default="", help="Manual SoT string")
    parser.add_argument(
        "--sot-file", action="append", default=[], help="Extra SoT file (repo-relative)"
    )
    parser.add_argument(
        "--max-chars", type=int, default=0, help="Max output chars (0 = no limit)"
    )
    args = parser.parse_args()

    repo_root = os.path.realpath(args.repo_root)
    if not os.path.isdir(repo_root):
        eprint(f"repo root not found: {repo_root}")
        return 1

    issue: Optional[Dict[str, str]] = None
    if args.issue_json:
        issue = read_issue_json(args.issue_json)
    elif args.issue_body_file:
        issue = {
            "title": "",
            "url": "",
            "number": "",
            "body": read_text(args.issue_body_file),
        }

    extra: List[str] = []
    for raw in args.sot_file:
        rel = resolve_ref_to_repo_path(repo_root, raw)
        extra.append(rel)

    try:
        out = build_sot(
            repo_root=repo_root,
            issue=issue,
            manual_sot=args.manual_sot,
            extra_files=extra,
            max_chars=args.max_chars,
        )
    except Exception as exc:
        eprint(str(exc))
        return 2

    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
