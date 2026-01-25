#!/usr/bin/env python3

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional


STATUS_ALLOWED = {"Approved", "Approved with nits", "Blocked", "Question"}
PRIORITY_ALLOWED = {"P0", "P1", "P2", "P3"}


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def die(errors: List[str]) -> int:
    for err in errors:
        eprint(f"- {err}")
    return 1


def is_repo_relative_path(path: str) -> bool:
    if not path:
        return False
    if path.startswith("/"):
        return False
    if path in {".", ".."}:
        return False
    parts = [p for p in path.split("/") if p]
    return ".." not in parts


def validate_review(
    obj: Dict[str, Any],
    expected_scope_id: Optional[str],
) -> List[str]:
    errors: List[str] = []

    required = {
        "schema_version",
        "scope_id",
        "status",
        "findings",
        "questions",
        "overall_explanation",
    }

    missing = required - set(obj.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
        return errors

    extra = set(obj.keys()) - required
    if extra:
        errors.append(f"unexpected keys: {sorted(extra)}")

    if obj.get("schema_version") != 3:
        errors.append("schema_version must be 3")

    scope_id = obj.get("scope_id")
    if not isinstance(scope_id, str) or not scope_id:
        errors.append("scope_id must be a non-empty string")
    elif expected_scope_id is not None and scope_id != expected_scope_id:
        errors.append(
            f"scope_id mismatch: expected {expected_scope_id}, got {scope_id}"
        )

    status = obj.get("status")
    if status not in STATUS_ALLOWED:
        errors.append(f"status must be one of {sorted(STATUS_ALLOWED)}")

    findings = obj.get("findings")
    if not isinstance(findings, list):
        errors.append("findings must be an array")
        findings = []

    questions = obj.get("questions")
    if not isinstance(questions, list) or any(
        not isinstance(x, str) for x in questions
    ):
        errors.append("questions must be an array of strings")
        questions = []

    overall_explanation = obj.get("overall_explanation")
    if not isinstance(overall_explanation, str) or not overall_explanation:
        errors.append("overall_explanation must be a non-empty string")

    # Validate findings
    for idx, item in enumerate(findings):
        if not isinstance(item, dict):
            errors.append(f"findings[{idx}] is not an object")
            continue
        required_finding_keys = {"title", "body", "priority", "code_location"}
        for k in sorted(required_finding_keys):
            if k not in item:
                errors.append(f"findings[{idx}] missing key: {k}")

        extra_finding = set(item.keys()) - required_finding_keys
        if extra_finding:
            errors.append(f"findings[{idx}] unexpected keys: {sorted(extra_finding)}")

        title = item.get("title")
        if not isinstance(title, str) or not title:
            errors.append(f"findings[{idx}].title must be a non-empty string")
        elif len(title) > 120:
            errors.append(f"findings[{idx}].title must be <= 120 chars")

        body = item.get("body")
        if not isinstance(body, str) or not body:
            errors.append(f"findings[{idx}].body must be a non-empty string")

        priority = item.get("priority")
        if not isinstance(priority, str) or priority not in PRIORITY_ALLOWED:
            errors.append(
                f"findings[{idx}].priority must be one of {sorted(PRIORITY_ALLOWED)}"
            )

        code_location = item.get("code_location")
        if not isinstance(code_location, dict):
            errors.append(f"findings[{idx}].code_location must be an object")
            continue

        required_code_location_keys = {"repo_relative_path", "line_range"}
        missing_code_location = required_code_location_keys - set(code_location.keys())
        if missing_code_location:
            errors.append(
                f"findings[{idx}].code_location missing keys: {sorted(missing_code_location)}"
            )
        extra_code_location = set(code_location.keys()) - required_code_location_keys
        if extra_code_location:
            errors.append(
                f"findings[{idx}].code_location unexpected keys: {sorted(extra_code_location)}"
            )

        repo_relative_path = code_location.get("repo_relative_path")
        if not isinstance(repo_relative_path, str) or not is_repo_relative_path(
            repo_relative_path
        ):
            errors.append(
                f"findings[{idx}].code_location.repo_relative_path must be repo-relative (no '..', not absolute)"
            )

        line_range = code_location.get("line_range")
        if not isinstance(line_range, dict):
            errors.append(f"findings[{idx}].code_location.line_range must be an object")
            continue

        required_line_range_keys = {"start", "end"}
        missing_line_range = required_line_range_keys - set(line_range.keys())
        if missing_line_range:
            errors.append(
                f"findings[{idx}].code_location.line_range missing keys: {sorted(missing_line_range)}"
            )
        extra_line_range = set(line_range.keys()) - required_line_range_keys
        if extra_line_range:
            errors.append(
                f"findings[{idx}].code_location.line_range unexpected keys: {sorted(extra_line_range)}"
            )

        start = line_range.get("start")
        end = line_range.get("end")
        if not isinstance(start, int) or start < 1:
            errors.append(
                f"findings[{idx}].code_location.line_range.start must be int >= 1"
            )
        if not isinstance(end, int) or end < 1:
            errors.append(
                f"findings[{idx}].code_location.line_range.end must be int >= 1"
            )
        if isinstance(start, int) and isinstance(end, int) and end < start:
            errors.append(
                f"findings[{idx}].code_location.line_range.end must be >= start"
            )

    # Cross-field constraints
    if status == "Approved":
        if len(findings) != 0:
            errors.append("Approved must have findings=[]")
        if len(questions) != 0:
            errors.append("Approved must have questions=[]")

    if status == "Approved with nits":
        blocking = [
            f
            for f in findings
            if isinstance(f, dict) and f.get("priority") in ("P0", "P1")
        ]
        if blocking:
            errors.append("Approved with nits must not include P0/P1 findings")
        if len(questions) != 0:
            errors.append("Approved with nits must have questions=[]")

    if status == "Blocked":
        blocking = [
            f
            for f in findings
            if isinstance(f, dict) and f.get("priority") in ("P0", "P1")
        ]
        if not blocking:
            errors.append("Blocked must include at least one P0/P1 finding")

    if status == "Question":
        if len(questions) == 0:
            errors.append("Question must include at least one question")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate review.json output.")
    parser.add_argument("path", help="Path to review.json")
    parser.add_argument("--scope-id", default="", help="Expected scope_id")
    parser.add_argument(
        "--format", action="store_true", help="Rewrite JSON with pretty formatting"
    )
    args = parser.parse_args()

    if not os.path.isfile(args.path):
        eprint(f"file not found: {args.path}")
        return 1

    try:
        with open(args.path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        eprint(f"invalid JSON: {exc}")
        return 1

    if not isinstance(data, dict):
        eprint("root must be an object")
        return 1

    expected_scope_id = args.scope_id.strip() or None
    errors = validate_review(data, expected_scope_id)
    if errors:
        eprint("review.json validation failed:")
        return die(errors)

    if args.format:
        tmp = f"{args.path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        os.replace(tmp, args.path)

    print(f"OK: {args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
