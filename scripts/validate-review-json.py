#!/usr/bin/env python3

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional


STATUS_ALLOWED = {"Approved", "Approved with nits", "Blocked", "Question"}
OVERALL_CORRECTNESS_ALLOWED = {"patch is correct", "patch is incorrect"}


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
    expected_facet_slug: Optional[str],
) -> List[str]:
    errors: List[str] = []

    required = {
        "schema_version",
        "scope_id",
        "facet",
        "facet_slug",
        "status",
        "findings",
        "questions",
        "uncertainty",
        "overall_correctness",
        "overall_explanation",
        "overall_confidence_score",
    }

    missing = required - set(obj.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
        return errors

    if obj.get("schema_version") != 2:
        errors.append("schema_version must be 2")

    scope_id = obj.get("scope_id")
    if not isinstance(scope_id, str) or not scope_id:
        errors.append("scope_id must be a non-empty string")
    elif expected_scope_id is not None and scope_id != expected_scope_id:
        errors.append(
            f"scope_id mismatch: expected {expected_scope_id}, got {scope_id}"
        )

    facet = obj.get("facet")
    if not isinstance(facet, str) or not facet:
        errors.append("facet must be a non-empty string")

    facet_slug = obj.get("facet_slug")
    if not isinstance(facet_slug, str) or not facet_slug:
        errors.append("facet_slug must be a non-empty string")
    elif expected_facet_slug is not None and facet_slug != expected_facet_slug:
        errors.append(
            f"facet_slug mismatch: expected {expected_facet_slug}, got {facet_slug}"
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

    uncertainty = obj.get("uncertainty")
    if not isinstance(uncertainty, list) or any(
        not isinstance(x, str) for x in uncertainty
    ):
        errors.append("uncertainty must be an array of strings")

    overall_correctness = obj.get("overall_correctness")
    if overall_correctness not in OVERALL_CORRECTNESS_ALLOWED:
        errors.append(
            f"overall_correctness must be one of {sorted(OVERALL_CORRECTNESS_ALLOWED)}"
        )

    overall_explanation = obj.get("overall_explanation")
    if not isinstance(overall_explanation, str) or not overall_explanation:
        errors.append("overall_explanation must be a non-empty string")

    overall_confidence = obj.get("overall_confidence_score")
    if not isinstance(overall_confidence, (int, float)) or not (
        0.0 <= float(overall_confidence) <= 1.0
    ):
        errors.append("overall_confidence_score must be a number 0.0-1.0")

    # Validate findings
    for idx, item in enumerate(findings):
        if not isinstance(item, dict):
            errors.append(f"findings[{idx}] is not an object")
            continue
        for k in ["title", "body", "confidence_score", "priority", "code_location"]:
            if k not in item:
                errors.append(f"findings[{idx}] missing key: {k}")

        title = item.get("title")
        if not isinstance(title, str) or not title:
            errors.append(f"findings[{idx}].title must be a non-empty string")
        elif len(title) > 120:
            errors.append(f"findings[{idx}].title must be <= 120 chars")

        body = item.get("body")
        if not isinstance(body, str) or not body:
            errors.append(f"findings[{idx}].body must be a non-empty string")

        confidence = item.get("confidence_score")
        if not isinstance(confidence, (int, float)) or not (
            0.0 <= float(confidence) <= 1.0
        ):
            errors.append(f"findings[{idx}].confidence_score must be a number 0.0-1.0")

        priority = item.get("priority")
        if not isinstance(priority, int) or not (0 <= priority <= 3):
            errors.append(f"findings[{idx}].priority must be an int 0-3")

        code_location = item.get("code_location")
        if not isinstance(code_location, dict):
            errors.append(f"findings[{idx}].code_location must be an object")
            continue

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
    if (
        status in {"Blocked", "Question"}
        and overall_correctness != "patch is incorrect"
    ):
        errors.append(
            "Blocked/Question must have overall_correctness='patch is incorrect'"
        )
    if (
        status in {"Approved", "Approved with nits"}
        and overall_correctness != "patch is correct"
    ):
        errors.append(
            "Approved/Approved with nits must have overall_correctness='patch is correct'"
        )

    if status == "Approved":
        if len(findings) != 0:
            errors.append("Approved must have findings=[]")
        if len(questions) != 0:
            errors.append("Approved must have questions=[]")

    if status == "Approved with nits":
        blocking = [
            f for f in findings if isinstance(f, dict) and f.get("priority") in (0, 1)
        ]
        if blocking:
            errors.append("Approved with nits must not include priority 0/1 findings")
        if len(questions) != 0:
            errors.append("Approved with nits must have questions=[]")

    if status == "Blocked":
        blocking = [
            f for f in findings if isinstance(f, dict) and f.get("priority") in (0, 1)
        ]
        if not blocking:
            errors.append("Blocked must include at least one priority 0/1 finding")

    if status == "Question":
        if len(questions) == 0:
            errors.append("Question must include at least one question")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate review.json output.")
    parser.add_argument("path", help="Path to review.json")
    parser.add_argument("--scope-id", default="", help="Expected scope_id")
    parser.add_argument("--facet-slug", default="", help="Expected facet_slug")
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
    expected_facet_slug = args.facet_slug.strip() or None
    errors = validate_review(data, expected_scope_id, expected_facet_slug)
    if errors:
        eprint("review.json validation failed:")
        return die(errors)

    if args.format:
        tmp = f"{args.path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=True, indent=2)
            fh.write("\n")
        os.replace(tmp, args.path)

    print(f"OK: {args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
