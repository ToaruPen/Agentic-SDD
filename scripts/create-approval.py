#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

MODE_ALLOWED = {"impl", "tdd", "custom"}


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def now_utc_z() -> str:
    # Agentic-SDD datetime rule: YYYY-MM-DDTHH:mm:ssZ (UTC, no milliseconds).
    return (
        datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
    )


def git_repo_root() -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")

    p = subprocess.run(  # noqa: S603
        [git_bin, "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,  # noqa: S603
    )
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
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def write_json(path: str, obj: dict, force: bool) -> None:
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

    approved_at = args.approved_at.strip() or now_utc_z()
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", approved_at):
        eprint("Invalid --approved-at (expected format: YYYY-MM-DDTHH:mm:ssZ)")
        return 2

    try:
        repo_root = (
            os.path.realpath(args.repo_root) if args.repo_root else git_repo_root()
        )
    except Exception as exc:  # noqa: BLE001
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
    except Exception as exc:  # noqa: BLE001
        eprint(f"Failed to read estimate.md (utf-8 required): {exc}")
        return 2

    estimate_hash = sha256_prefixed(normalize_text_for_hash(estimate_text))

    record = {
        "schema_version": 1,
        "issue_number": args.issue,
        "mode": mode,
        "approved_at": approved_at,
        "estimate_hash": estimate_hash,
        "approver": str(args.approver),
    }

    try:
        write_json(approval_json, record, force=bool(args.force))
    except FileExistsError as exc:
        eprint(str(exc))
        return 2
    except Exception as exc:  # noqa: BLE001
        eprint(f"Failed to write approval.json: {exc}")
        return 1

    rel = os.path.relpath(approval_json, repo_root)
    print(f"OK: wrote {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
