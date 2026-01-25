#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

from sot_refs import find_issue_ref, resolve_ref_to_repo_path


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def truncate_keep_tail(text: str, max_chars: int, tail_chars: int = 2048) -> str:
    if max_chars <= 0 or len(text) <= max_chars:
        return text

    marker = "\n\n[TRUNCATED]\n\n"
    if max_chars <= len(marker):
        out = marker[:max_chars]
        if not out.endswith("\n"):
            out = out[:-1] + "\n" if max_chars > 0 else ""
        return out

    budget = max_chars - len(marker)
    tail_len = min(tail_chars, budget)
    head_len = budget - tail_len

    head = text[:head_len]
    tail = text[-tail_len:] if tail_len > 0 else ""

    # Prefer cutting on line boundaries to reduce partial lines.
    head_nl = head.rfind("\n")
    if head_nl > 0:
        head = head[: head_nl + 1]

    if tail:
        tail_start = len(text) - tail_len
        tail_nl = text.find("\n", tail_start)
        if tail_nl != -1 and tail_nl + 1 < len(text):
            tail = text[tail_nl + 1 :]

    out = head + marker + tail

    if not out.endswith("\n"):
        if len(out) < max_chars:
            out += "\n"
        elif max_chars > 0:
            out = out[:-1] + "\n"

    if len(out) > max_chars:
        out = out[:max_chars]
        if max_chars > 0 and not out.endswith("\n"):
            out = out[:-1] + "\n"

    return out


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
    return truncate_keep_tail(out, max_chars=max_chars, tail_chars=2048)


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
