from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    scripts_dir = repo_root / "scripts"
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    module_path = scripts_dir / "validate-review-json.py"
    spec = importlib.util.spec_from_file_location("validate_review_json", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


class TestIsRepoRelativePath:
    def test_valid_relative_path(self) -> None:
        assert MODULE.is_repo_relative_path("docs/readme.md")
        assert MODULE.is_repo_relative_path("src/lib/module.py")

    def test_empty_path(self) -> None:
        assert not MODULE.is_repo_relative_path("")

    def test_absolute_path(self) -> None:
        assert not MODULE.is_repo_relative_path("/etc/passwd")

    def test_parent_traversal(self) -> None:
        assert not MODULE.is_repo_relative_path("..")
        assert not MODULE.is_repo_relative_path("../foo")
        assert not MODULE.is_repo_relative_path("foo/..")

    def test_current_directory(self) -> None:
        assert not MODULE.is_repo_relative_path(".")


class TestValidateReview:
    def test_valid_review(self) -> None:
        obj = {
            "schema_version": 3,
            "scope_id": "test-scope",
            "status": "Approved",
            "findings": [],
            "questions": [],
            "overall_explanation": "All good",
        }
        errors = MODULE.validate_review(obj, "test-scope")
        assert errors == []

    def test_wrong_scope_id(self) -> None:
        obj = {
            "schema_version": 3,
            "scope_id": "wrong-scope",
            "status": "Approved",
            "findings": [],
            "questions": [],
            "overall_explanation": "All good",
        }
        errors = MODULE.validate_review(obj, "test-scope")
        assert any("scope_id mismatch" in e for e in errors)

    def test_missing_required_field(self) -> None:
        obj: dict[str, str] = {}
        errors = MODULE.validate_review(obj, "test-scope")
        assert len(errors) > 0

    def test_invalid_status(self) -> None:
        obj = {
            "schema_version": 3,
            "scope_id": "test-scope",
            "status": "InvalidStatus",
            "findings": [],
            "questions": [],
            "overall_explanation": "All good",
        }
        errors = MODULE.validate_review(obj, "test-scope")
        assert any("status" in e for e in errors)

    def test_valid_status_values(self) -> None:
        for status in ["Approved", "Blocked", "Question"]:
            obj = {
                "schema_version": 3,
                "scope_id": "test-scope",
                "status": status,
                "findings": [],
                "questions": [],
                "overall_explanation": "Check",
            }
            errors = MODULE.validate_review(obj, "test-scope")
            status_errors = [e for e in errors if "status" in e.lower()]
            assert status_errors == [], f"Status {status} should be valid"

    def test_finding_with_required_fields(self) -> None:
        obj = {
            "schema_version": 3,
            "scope_id": "test-scope",
            "status": "Blocked",
            "findings": [
                {
                    "title": "Test finding",
                    "body": "Description",
                    "priority": "P1",
                    "code_location": {
                        "repo_relative_path": "test.py",
                        "line_range": {"start": 1, "end": 10},
                    },
                }
            ],
            "questions": [],
            "overall_explanation": "Issue found",
        }
        errors = MODULE.validate_review(obj, "test-scope")
        finding_errors = [e for e in errors if "finding" in e.lower()]
        assert finding_errors == []

    def test_finding_missing_title(self) -> None:
        obj = {
            "schema_version": 3,
            "scope_id": "test-scope",
            "status": "Blocked",
            "findings": [{"body": "No title"}],
            "questions": [],
            "overall_explanation": "Issue",
        }
        errors = MODULE.validate_review(obj, "test-scope")
        assert len(errors) > 0
