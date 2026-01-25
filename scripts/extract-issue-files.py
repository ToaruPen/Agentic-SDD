#!/usr/bin/env python3

import argparse
import json
import os
import re
import subprocess
import sys
from typing import List, Sequence, Set, Tuple


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

    # Angle brackets
    if ref.startswith("<") and ref.endswith(">"):
        ref = ref[1:-1].strip()

    # Backticks
    if ref.startswith("`") and ref.endswith("`"):
        ref = ref[1:-1].strip()

    # Strip fragment
    ref = ref.split("#", 1)[0].strip()
    return ref


def resolve_ref_to_repo_path(repo_root: str, ref: str) -> str:
    ref = normalize_reference(ref)
    if not ref:
        raise ValueError("empty reference")

    # Ignore URLs
    if ref.startswith("http://") or ref.startswith("https://"):
        raise ValueError(f"unsupported URL reference: {ref}")

    if os.path.isabs(ref):
        abs_path = os.path.realpath(ref)
        repo_abs = os.path.realpath(repo_root)
        if not abs_path.startswith(repo_abs + os.sep):
            raise ValueError(f"absolute path outside repo: {ref}")
        rel = os.path.relpath(abs_path, repo_abs).replace(os.sep, "/")
        if not is_safe_repo_relative(rel):
            raise ValueError(f"unsafe repo-relative path: {rel}")
        return rel

    rel = ref
    if rel.startswith("./"):
        rel = rel[2:]
    rel = rel.replace("\\", "/")
    rel = os.path.normpath(rel).replace(os.sep, "/")
    if not is_safe_repo_relative(rel):
        raise ValueError(f"unsafe repo-relative path: {rel}")
    return rel


def gh_issue_body(issue: str, gh_repo: str) -> str:
    cmd: List[str] = ["gh"]
    if gh_repo:
        cmd.extend(["-R", gh_repo])
    cmd.extend(["issue", "view", issue, "--json", "body"])

    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise RuntimeError("gh not found (required for --issue)")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace")
        raise RuntimeError(f"gh issue view failed: {msg.strip()}")

    data = json.loads(out.decode("utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError("gh output must be a JSON object")
    body = str(data.get("body") or "")
    return body


HEADING_RE = re.compile(
    r"^(#{2,6})\s*(変更対象ファイル[^\n]*|Change\s+targets?[^\n]*)\s*$"
)

# Backtick-wrapped paths are the canonical, deterministic form.
BACKTICK_RE = re.compile(r"`([^`]+)`")

# Limited fallback: only bullet-ish lines, only paths containing '/'.
BULLET_PATH_RE = re.compile(
    r"^\s*[-*]\s*(?:\[[ xX]\]\s*)?(?P<path>(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+)\s*$"
)


def extract_section_lines(body: str) -> Tuple[List[str], bool]:
    lines = body.splitlines()
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if not m:
            continue
        level = len(m.group(1))
        start = i + 1
        end = len(lines)
        for j in range(start, len(lines)):
            m2 = re.match(r"^(#{1,6})\s+", lines[j])
            if not m2:
                continue
            if len(m2.group(1)) <= level:
                end = j
                break
        return lines[start:end], True
    return lines, False


def extract_paths(repo_root: str, lines: Sequence[str]) -> List[str]:
    out: Set[str] = set()

    for line in lines:
        for raw in BACKTICK_RE.findall(line):
            try:
                out.add(resolve_ref_to_repo_path(repo_root, raw))
            except Exception:
                continue

        if "`" in line:
            continue

        m = BULLET_PATH_RE.match(line)
        if m:
            try:
                out.add(resolve_ref_to_repo_path(repo_root, m.group("path")))
            except Exception:
                continue

    return sorted(out)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract declared change-target files from an Issue body."
    )
    parser.add_argument("--repo-root", required=True, help="Repo root path")

    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--issue", default="", help="GitHub Issue number or URL (uses gh)")
    src.add_argument(
        "--issue-body-file",
        default="",
        help="Path to local file containing issue body (Markdown), or a JSON object with {body: ...}",
    )
    src.add_argument(
        "--issue-json-file", default="", help="Path to JSON containing {body: ...}"
    )

    parser.add_argument("--gh-repo", default="", help="OWNER/REPO for gh")
    parser.add_argument(
        "--mode",
        choices=["section", "anywhere"],
        default="section",
        help="Extraction mode (default: section)",
    )
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Allow empty result (default: fail)",
    )
    parser.add_argument(
        "--format",
        choices=["lines", "json"],
        default="lines",
        help="Output format (default: lines)",
    )

    args = parser.parse_args()

    repo_root = os.path.realpath(args.repo_root)
    if not os.path.isdir(repo_root):
        eprint(f"repo root not found: {repo_root}")
        return 2

    body = ""
    try:
        if args.issue:
            body = gh_issue_body(args.issue, args.gh_repo)
        elif args.issue_body_file:
            raw = read_text(args.issue_body_file)
            body = raw
            # Convenience: allow passing `gh issue view --json body` output.
            try:
                data = json.loads(raw)
                if isinstance(data, dict) and isinstance(data.get("body"), str):
                    body = data["body"]
            except Exception:
                pass
        elif args.issue_json_file:
            data = json.loads(read_text(args.issue_json_file))
            if not isinstance(data, dict):
                raise ValueError("issue json must be an object")
            body = str(data.get("body") or "")
        else:
            raise ValueError("no input")
    except Exception as exc:
        eprint(str(exc))
        return 2

    section_lines, has_section = extract_section_lines(body)
    if args.mode == "section" and not has_section:
        eprint(
            "Missing required section: '変更対象ファイル' (cannot determine change targets deterministically)"
        )
        return 2

    scan_lines = section_lines if args.mode == "section" else body.splitlines()
    paths = extract_paths(repo_root, scan_lines)
    if not paths and not args.allow_empty:
        eprint(
            "No change-target files found. Fill '変更対象ファイル（推定）' with repo-relative paths."
        )
        return 2

    if args.format == "json":
        sys.stdout.write(json.dumps(paths, ensure_ascii=True))
        sys.stdout.write("\n")
        return 0

    for p in paths:
        sys.stdout.write(p + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
