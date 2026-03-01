#!/usr/bin/env python3

import argparse
import json
import re
import shlex
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from _lib.approval_constants import MODE_ALLOWED, MODE_SOURCE_ALLOWED
from _lib.git_utils import (
    current_branch,
    eprint,
    extract_issue_number_from_branch,
    git_repo_root,
    normalize_text_for_hash,
    run,
    sha256_prefixed,
)

EXIT_GATE_BLOCKED = 2
_ = run


def read_utf8_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def display_path(path: str, repo_root: str) -> str:
    p = Path(path)
    root = Path(repo_root)
    try:
        return str(p.relative_to(root))
    except ValueError:
        return str(p)


def approval_paths(repo_root: str, issue_number: int) -> tuple[str, str]:
    base = Path(repo_root) / ".agentic-sdd" / "approvals" / f"issue-{issue_number}"
    return str(base / "approval.json"), str(base / "estimate.md")


def resolve_approval_script(repo_root: str, candidates: tuple[str, ...]) -> str:
    for rel in candidates:
        if (Path(repo_root) / rel).is_file():
            return rel
    return candidates[0]


def load_approval_json(path: str) -> dict[str, Any]:
    raw = read_utf8_text(path)
    obj = json.loads(raw)
    if not isinstance(obj, dict):
        raise ValueError("approval.json must be a JSON object")
    return obj


def pick_estimate_hash_field(obj: dict[str, Any]) -> tuple[str, str]:
    estimate_hash = obj.get("estimate_hash")
    estimate_sha256 = obj.get("estimate_sha256")
    if (
        estimate_hash is not None
        and estimate_sha256 is not None
        and estimate_hash != estimate_sha256
    ):
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


def validate_approval(obj: dict[str, Any], expected_issue_number: int) -> None:
    required = {
        "schema_version",
        "issue_number",
        "mode",
        "mode_source",
        "mode_reason",
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

    mode_source = obj.get("mode_source")
    if not isinstance(mode_source, str) or mode_source not in MODE_SOURCE_ALLOWED:
        raise ValueError(f"mode_source must be one of {sorted(MODE_SOURCE_ALLOWED)}")

    mode_reason_raw = obj.get("mode_reason")
    if not isinstance(mode_reason_raw, str):
        raise ValueError("mode_reason must be a non-empty string")
    mode_reason = mode_reason_raw.strip()
    if not mode_reason:
        raise ValueError("mode_reason must be a non-empty string")

    approved_at = obj.get("approved_at")
    if not isinstance(approved_at, str):
        raise ValueError("approved_at must be a non-empty string")
    approved_at_value = approved_at.strip()
    if not approved_at_value:
        raise ValueError("approved_at must be a non-empty string")
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", approved_at_value):
        raise ValueError(
            "approved_at must be ISO 8601 UTC timestamp like YYYY-MM-DDTHH:mm:ssZ"
        )
    try:
        datetime.strptime(approved_at_value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise ValueError("approved_at must be a valid UTC timestamp") from exc

    approver = obj.get("approver")
    if not isinstance(approver, str):
        raise ValueError("approver must be a non-empty string")
    if not approver.strip():
        raise ValueError("approver must be a non-empty string")


def gate_blocked(msg: str, create_script: str, validate_script: str) -> int:
    eprint("[agentic-sdd gate] BLOCKED")
    eprint("")
    eprint(msg.rstrip())
    eprint("")
    eprint("Next action:")
    eprint("1) Run /estimation and get explicit approval (mode + Yes).")
    eprint("2) Save the approved estimate to:")
    eprint("   .agentic-sdd/approvals/issue-<n>/estimate.md")
    eprint("3) Create/refresh approval.json:")
    eprint(
        f"   python3 {create_script} --issue <n> --mode <impl|tdd|custom> --mode-source <agent-heuristic|user-choice|operator-override> --mode-reason '<reason>'"
    )
    eprint("4) Validate:")
    eprint(f"   python3 {validate_script}")
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
        repo_root = str(
            Path(args.repo_root).resolve()
            if args.repo_root
            else Path(git_repo_root()).resolve()
        )
    except RuntimeError as exc:
        eprint(f"[agentic-sdd gate] error: {exc}")
        return 1

    try:
        branch = current_branch(repo_root)
    except RuntimeError as exc:
        eprint(f"[agentic-sdd gate] error: {exc}")
        return 1
    issue_number = extract_issue_number_from_branch(branch)

    create_script = resolve_approval_script(
        repo_root,
        (
            str(Path("scripts") / "approval" / "create_approval.py"),
            str(Path("scripts") / "create-approval.py"),
        ),
    )
    validate_script = resolve_approval_script(
        repo_root,
        (
            str(Path("scripts") / "gates" / "validate_approval.py"),
            str(Path("scripts") / "validate-approval.py"),
        ),
    )

    # Only enforce on branches that clearly indicate an Issue.
    if issue_number is None:
        return 0

    approval_json, estimate_md = approval_paths(repo_root, issue_number)

    if not Path(estimate_md).is_file():
        return gate_blocked(
            f"Missing estimate snapshot file: {display_path(estimate_md, repo_root)}",
            create_script,
            validate_script,
        )

    if not Path(approval_json).is_file():
        return gate_blocked(
            f"Missing approval record file: {display_path(approval_json, repo_root)}",
            create_script,
            validate_script,
        )

    try:
        estimate_text = read_utf8_text(estimate_md)
    except (OSError, UnicodeDecodeError) as exc:
        return gate_blocked(
            f"Failed to read estimate.md (utf-8 required): {exc}",
            create_script,
            validate_script,
        )

    computed_hash = sha256_prefixed(normalize_text_for_hash(estimate_text))

    try:
        obj = load_approval_json(approval_json)
        validate_approval(obj, expected_issue_number=issue_number)
        field, recorded_hash = pick_estimate_hash_field(obj)
        if not re.match(r"^sha256:[0-9a-f]{64}$", recorded_hash):
            raise ValueError(f"{field} must be 'sha256:<64 lowercase hex>'")
        if recorded_hash != computed_hash:
            mode_for_cmd = shlex.quote(str(obj.get("mode") or "<mode>"))
            mode_source_for_cmd = shlex.quote(str(obj.get("mode_source") or "<source>"))
            mode_reason_for_cmd = shlex.quote(str(obj.get("mode_reason") or "<reason>"))
            return gate_blocked(
                "Estimate drift detected.\n"
                f"- recorded: {recorded_hash}\n"
                f"- computed: {computed_hash}\n"
                "If you updated the estimate, re-run Phase 2.5 and recreate approval.json:\n"
                f"  python3 {create_script} --issue {issue_number} --mode {mode_for_cmd} --mode-source {mode_source_for_cmd} --mode-reason {mode_reason_for_cmd} --force",
                create_script,
                validate_script,
            )
    except KeyError as exc:
        return gate_blocked(
            f"Invalid approval.json: {exc}", create_script, validate_script
        )
    except json.JSONDecodeError as exc:
        return gate_blocked(
            f"Invalid JSON in approval.json: {exc}",
            create_script,
            validate_script,
        )
    except ValueError as exc:
        return gate_blocked(
            f"Invalid approval.json: {exc}", create_script, validate_script
        )
    except OSError as exc:
        return gate_blocked(
            f"Failed to read approval.json (utf-8 required): {exc}",
            create_script,
            validate_script,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
