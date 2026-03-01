#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import argparse
import hashlib
import json
import os
import re
import shutil
from datetime import UTC, datetime
from typing import Any

from _lib.approval_constants import MODE_ALLOWED, MODE_SOURCE_ALLOWED
from _lib.subprocess_utils import run_cmd


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def now_utc_z() -> str:
    # Agentic-SDD datetime rule: YYYY-MM-DDTHH:mm:ssZ (UTC, no milliseconds).
    return datetime.now(UTC).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_repo_root() -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")

    try:
        p = run_cmd([git_bin, "rev-parse", "--show-toplevel"], check=False)
    except OSError as exc:
        raise RuntimeError("Not in a git repository; cannot locate repo root.") from exc
    root = (p.stdout or "").strip()
    if p.returncode != 0 or not root:
        raise RuntimeError("Not in a git repository; cannot locate repo root.")
    return os.path.realpath(root)


def normalize_text_for_hash(text: str) -> bytes:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if not text.endswith("\n"):
        text += "\n"
    return text.encode("utf-8")


def sha256_prefixed(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return f"sha256:{h.hexdigest()}"


def approval_dir(repo_root: str, issue_number: int) -> str:
    return os.path.join(repo_root, ".agentic-sdd", "approvals", f"issue-{issue_number}")


def ensure_parent_dir(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)


def read_utf8_text(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_json(path: str, obj: dict[str, Any], force: bool) -> None:
    if os.path.exists(path) and not force:
        raise FileExistsError(f"File already exists: {path} (use --force to overwrite)")
    ensure_parent_dir(path)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True))
        fh.write("\n")
    os.replace(tmp, path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a local approval record bound to an estimate snapshot."
    )
    parser.add_argument("--issue", type=int, required=True, help="Issue number")
    parser.add_argument("--mode", required=True, help="impl|tdd|custom")
    parser.add_argument(
        "--approver", default="user", help="Approver label (default: user)"
    )
    parser.add_argument(
        "--approved-at",
        default="",
        help="ISO 8601 UTC timestamp (YYYY-MM-DDTHH:mm:ssZ). Default: now (UTC)",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite approval.json")
    parser.add_argument(
        "--mode-source",
        required=True,
        help="How the mode was selected: agent-heuristic|user-choice|operator-override",
    )
    parser.add_argument(
        "--mode-reason",
        required=True,
        help="Free-text explanation of why this mode was selected",
    )
    parser.add_argument(
        "--repo-root",
        default="",
        help="Override repo root (default: auto-detect via git)",
    )
    args = parser.parse_args()

    if args.issue < 0:
        eprint("Issue number must be >= 0")
        return 2

    mode = str(args.mode)
    if mode not in MODE_ALLOWED:
        eprint(f"Invalid --mode: {mode} (expected one of {sorted(MODE_ALLOWED)})")
        return 2

    mode_source = str(args.mode_source)
    if mode_source not in MODE_SOURCE_ALLOWED:
        eprint(
            f"Invalid --mode-source: {mode_source} (expected one of {sorted(MODE_SOURCE_ALLOWED)})"
        )
        return 2

    mode_reason = str(args.mode_reason).strip()
    if not mode_reason:
        eprint("--mode-reason must be a non-empty string")
        return 2

    approved_at = args.approved_at.strip() or now_utc_z()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", approved_at):
        eprint("Invalid --approved-at (expected format: YYYY-MM-DDTHH:mm:ssZ)")
        return 2
    try:
        datetime.strptime(approved_at, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        eprint("Invalid --approved-at (invalid date/time value)")
        return 2

    try:
        repo_root = (
            os.path.realpath(args.repo_root) if args.repo_root else git_repo_root()
        )
    except RuntimeError as exc:
        eprint(f"Failed to locate repo root: {exc}")
        return 1

    base = approval_dir(repo_root, args.issue)
    estimate_md = os.path.join(base, "estimate.md")
    approval_json = os.path.join(base, "approval.json")

    if not os.path.isfile(estimate_md):
        eprint(f"Missing estimate snapshot file: {estimate_md}")
        eprint("Create it first (copy the approved estimate text into that file).")
        return 2

    try:
        estimate_text = read_utf8_text(estimate_md)
    except OSError as exc:
        eprint(f"Failed to read estimate.md (utf-8 required): {exc}")
        return 2

    estimate_hash = sha256_prefixed(normalize_text_for_hash(estimate_text))

    record = {
        "schema_version": 1,
        "issue_number": args.issue,
        "mode": mode,
        "mode_source": mode_source,
        "mode_reason": mode_reason,
        "approved_at": approved_at,
        "estimate_hash": estimate_hash,
        "approver": str(args.approver),
    }

    try:
        write_json(approval_json, record, force=bool(args.force))
    except FileExistsError as exc:
        eprint(str(exc))
        return 2
    except OSError as exc:
        eprint(f"Failed to write approval.json: {exc}")
        return 1

    rel = os.path.relpath(approval_json, repo_root)
    print(f"OK: wrote {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
