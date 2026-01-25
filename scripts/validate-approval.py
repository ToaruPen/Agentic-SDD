#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple


EXIT_GATE_BLOCKED = 2

MODE_ALLOWED = {"impl", "tdd", "custom"}


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: List[str],
    cwd: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def git_repo_root() -> str:
    try:
        p = run(["git", "rev-parse", "--show-toplevel"], check=True)
    except subprocess.CalledProcessError:
        raise RuntimeError("Not in a git repository; cannot locate repo root.")
    root = p.stdout.strip()
    if not root:
        raise RuntimeError("Failed to locate repo root via git.")
    return os.path.realpath(root)


def current_branch(repo_root: str) -> str:
    try:
        p = run(["git", "branch", "--show-current"], cwd=repo_root, check=False)
    except subprocess.CalledProcessError:
        return ""
    return p.stdout.strip()


def extract_issue_number_from_branch(branch: str) -> Optional[int]:
    m = re.search(r"\bissue-(\d+)\b", branch)
    if not m:
        return None
    try:
        n = int(m.group(1))
    except ValueError:
        return None
    if n < 0:
        return None
    return n


def normalize_text_for_hash(text: str) -> bytes:
    # Normalize line endings for cross-platform determinism.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if not text.endswith("\n"):
        text += "\n"
    return text.encode("utf-8")


def sha256_prefixed(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return f"sha256:{h.hexdigest()}"


def read_utf8_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def approval_paths(repo_root: str, issue_number: int) -> Tuple[str, str]:
    base = os.path.join(repo_root, ".agentic-sdd", "approvals", f"issue-{issue_number}")
    return os.path.join(base, "approval.json"), os.path.join(base, "estimate.md")


def load_approval_json(path: str) -> Dict[str, Any]:
    raw = read_utf8_text(path)
    obj = json.loads(raw)
    if not isinstance(obj, dict):
        raise ValueError("approval.json must be a JSON object")
    return obj


def pick_estimate_hash_field(obj: Dict[str, Any]) -> Tuple[str, str]:
    estimate_hash = obj.get("estimate_hash")
    estimate_sha256 = obj.get("estimate_sha256")
    if estimate_hash is not None and estimate_sha256 is not None:
        if estimate_hash != estimate_sha256:
            raise ValueError(
                "approval.json has both estimate_hash and estimate_sha256 but they differ"
            )
    if estimate_hash is None and estimate_sha256 is None:
        raise KeyError("missing estimate_hash (or estimate_sha256)")
    value = estimate_hash if estimate_hash is not None else estimate_sha256
    if not isinstance(value, str) or not value:
        raise ValueError("estimate_hash must be a non-empty string")
    field = "estimate_hash" if estimate_hash is not None else "estimate_sha256"
    return field, value


def validate_approval(obj: Dict[str, Any], expected_issue_number: int) -> None:
    required = {
        "schema_version",
        "issue_number",
        "mode",
        "approved_at",
        "approver",
    }

    missing = required - set(obj.keys())
    if missing:
        raise KeyError(f"missing keys: {sorted(missing)}")

    # estimate_hash/estimate_sha256 is validated separately.
    _field, _value = pick_estimate_hash_field(obj)

    extra_allowed = {"estimate_hash", "estimate_sha256"}
    extra = set(obj.keys()) - required - extra_allowed
    if extra:
        raise KeyError(f"unexpected keys: {sorted(extra)}")

    if obj.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")

    issue_number = obj.get("issue_number")
    if not isinstance(issue_number, int):
        raise ValueError("issue_number must be an integer")
    if issue_number != expected_issue_number:
        raise ValueError(
            f"issue_number mismatch: expected {expected_issue_number}, got {issue_number}"
        )

    mode = obj.get("mode")
    if not isinstance(mode, str) or mode not in MODE_ALLOWED:
        raise ValueError(f"mode must be one of {sorted(MODE_ALLOWED)}")

    approved_at = obj.get("approved_at")
    if not isinstance(approved_at, str) or not approved_at:
        raise ValueError("approved_at must be a non-empty string")
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", approved_at):
        raise ValueError(
            "approved_at must be ISO 8601 UTC timestamp like YYYY-MM-DDTHH:mm:ssZ"
        )

    approver = obj.get("approver")
    if not isinstance(approver, str) or not approver:
        raise ValueError("approver must be a non-empty string")


def gate_blocked(msg: str) -> int:
    eprint("[agentic-sdd gate] BLOCKED")
    eprint("")
    eprint(msg.rstrip())
    eprint("")
    eprint("Next action:")
    eprint("1) Run /estimation and get explicit approval (mode + Yes).")
    eprint("2) Save the approved estimate to:")
    eprint("   .agentic-sdd/approvals/issue-<n>/estimate.md")
    eprint("3) Create/refresh approval.json:")
    eprint("   python3 scripts/create-approval.py --issue <n> --mode <impl|tdd|custom>")
    eprint("4) Validate:")
    eprint("   python3 scripts/validate-approval.py")
    return EXIT_GATE_BLOCKED


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate local approval record for the current issue branch."
    )
    parser.add_argument(
        "--repo-root",
        default="",
        help="Override repo root (default: auto-detect via git)",
    )
    args = parser.parse_args()

    try:
        repo_root = (
            os.path.realpath(args.repo_root) if args.repo_root else git_repo_root()
        )
    except Exception as exc:  # noqa: BLE001
        eprint(f"[agentic-sdd gate] error: {exc}")
        return 1

    branch = current_branch(repo_root)
    issue_number = extract_issue_number_from_branch(branch)

    # Only enforce on branches that clearly indicate an Issue.
    if issue_number is None:
        return 0

    approval_json, estimate_md = approval_paths(repo_root, issue_number)

    if not os.path.isfile(estimate_md):
        return gate_blocked(
            f"Missing estimate snapshot file: {os.path.relpath(estimate_md, repo_root)}"
        )

    if not os.path.isfile(approval_json):
        return gate_blocked(
            f"Missing approval record file: {os.path.relpath(approval_json, repo_root)}"
        )

    try:
        estimate_text = read_utf8_text(estimate_md)
    except Exception as exc:  # noqa: BLE001
        return gate_blocked(f"Failed to read estimate.md (utf-8 required): {exc}")

    computed_hash = sha256_prefixed(normalize_text_for_hash(estimate_text))

    try:
        obj = load_approval_json(approval_json)
        validate_approval(obj, expected_issue_number=issue_number)
        field, recorded_hash = pick_estimate_hash_field(obj)
        if not re.match(r"^sha256:[0-9a-f]{64}$", recorded_hash):
            raise ValueError(f"{field} must be 'sha256:<64 lowercase hex>'")
        if recorded_hash != computed_hash:
            return gate_blocked(
                "Estimate drift detected.\n"
                f"- recorded: {recorded_hash}\n"
                f"- computed: {computed_hash}\n"
                "If you updated the estimate, re-run Phase 2.5 and recreate approval.json:\n"
                f"  python3 scripts/create-approval.py --issue {issue_number} --mode {obj.get('mode')} --force"
            )
    except KeyError as exc:
        return gate_blocked(f"Invalid approval.json: {exc}")
    except ValueError as exc:
        return gate_blocked(f"Invalid approval.json: {exc}")
    except json.JSONDecodeError as exc:
        return gate_blocked(f"Invalid JSON in approval.json: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
