#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import argparse
import json
import re
import subprocess
from collections.abc import Sequence

from _lib.io_helpers import eprint, read_text
from _lib.sot_refs import resolve_ref_to_repo_path
from _lib.subprocess_utils import check_output_cmd


def gh_issue_body(issue: str, gh_repo: str) -> str:
    cmd: list[str] = ["gh"]
    if gh_repo:
        cmd.extend(["-R", gh_repo])
    cmd.extend(["issue", "view", issue, "--json", "body"])

    try:
        out = check_output_cmd(cmd, stderr=subprocess.STDOUT, text=True, timeout=30)
    except FileNotFoundError as exc:
        raise RuntimeError("gh not found (required for --issue)") from exc
    except subprocess.CalledProcessError as exc:
        msg = exc.output or ""
        raise RuntimeError(f"gh issue view failed: {msg.strip()}") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("gh issue view timed out") from exc

    data = json.loads(out)
    if not isinstance(data, dict):
        raise RuntimeError("gh output must be a JSON object")
    return str(data.get("body") or "")


HEADING_RE = re.compile(
    r"^(#{2,6})\s*(変更対象ファイル[^\n]*|Change\s+targets?[^\n]*)\s*$"
)

# Backtick-wrapped paths are the canonical, deterministic form.
BACKTICK_RE = re.compile(r"`([^`]+)`")

# Limited fallback: only bullet-ish lines, only paths containing '/'.
BULLET_PATH_RE = re.compile(
    r"^\s*[-*]\s*(?:\[[ xX]\]\s*)?(?P<path>(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+)\s*$"
)


def extract_section_lines(body: str) -> tuple[list[str], bool]:
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


def extract_paths(repo_root: str, lines: Sequence[str]) -> list[str]:
    out: set[str] = set()

    for line in lines:
        for raw in BACKTICK_RE.findall(line):
            try:
                resolved = resolve_ref_to_repo_path(repo_root, raw)
            except ValueError:
                pass
            else:
                out.add(resolved)

        if "`" in line:
            continue

        m = BULLET_PATH_RE.match(line)
        if m:
            try:
                resolved = resolve_ref_to_repo_path(repo_root, m.group("path"))
            except ValueError:
                pass
            else:
                out.add(resolved)

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

    repo_root = str(Path(args.repo_root).resolve())
    if not Path(repo_root).is_dir():
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
            parsed = None
            try:
                parsed = json.loads(raw)
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, dict) and isinstance(parsed.get("body"), str):
                body = parsed["body"]
        elif args.issue_json_file:
            data = json.loads(read_text(args.issue_json_file))
            if not isinstance(data, dict):
                raise ValueError("issue json must be an object")
            body = str(data.get("body") or "")
        else:
            raise ValueError("no input")
    except (json.JSONDecodeError, OSError, RuntimeError, ValueError) as exc:
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
