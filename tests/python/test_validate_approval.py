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
    module_path = scripts_dir / "validate-approval.py"
    spec = importlib.util.spec_from_file_location("validate_approval", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


class TestExtractIssueNumberFromBranch:
    def test_issue_branch_format(self) -> None:
        result = MODULE.extract_issue_number_from_branch("feature/issue-123-desc")
        assert result == 123

    def test_issue_branch_simple(self) -> None:
        result = MODULE.extract_issue_number_from_branch("issue-456")
        assert result == 456

    def test_no_issue_number(self) -> None:
        result = MODULE.extract_issue_number_from_branch("main")
        assert result is None

    def test_numeric_only_branch(self) -> None:
        result = MODULE.extract_issue_number_from_branch("123")
        assert result is None

    def test_branch_with_issue_prefix(self) -> None:
        result = MODULE.extract_issue_number_from_branch("feature/2024-01-15-issue-789")
        assert result == 789


class TestNormalizeTextForHash:
    def test_returns_bytes(self) -> None:
        result = MODULE.normalize_text_for_hash("hello")
        assert isinstance(result, bytes)

    def test_empty_string(self) -> None:
        result = MODULE.normalize_text_for_hash("")
        assert result == b"\n"

    def test_adds_trailing_newline(self) -> None:
        result = MODULE.normalize_text_for_hash("test")
        assert result.endswith(b"\n")

    def test_normalizes_crlf(self) -> None:
        result = MODULE.normalize_text_for_hash("line\r\nline2")
        assert b"\r\n" not in result

    def test_deterministic(self) -> None:
        text = "some content"
        result1 = MODULE.normalize_text_for_hash(text)
        result2 = MODULE.normalize_text_for_hash(text)
        assert result1 == result2


class TestSha256Prefixed:
    def test_produces_sha256_prefix(self) -> None:
        result = MODULE.sha256_prefixed(b"test data")
        assert result.startswith("sha256:")

    def test_produces_hex_after_prefix(self) -> None:
        result = MODULE.sha256_prefixed(b"test data")
        hex_part = result[7:]
        assert all(c in "0123456789abcdef" for c in hex_part)

    def test_consistent_length(self) -> None:
        result1 = MODULE.sha256_prefixed(b"short")
        result2 = MODULE.sha256_prefixed(b"a" * 1000)
        assert len(result1) == len(result2)

    def test_deterministic(self) -> None:
        result1 = MODULE.sha256_prefixed(b"test")
        result2 = MODULE.sha256_prefixed(b"test")
        assert result1 == result2

    def test_different_inputs_different_outputs(self) -> None:
        result1 = MODULE.sha256_prefixed(b"test1")
        result2 = MODULE.sha256_prefixed(b"test2")
        assert result1 != result2


class TestPickEstimateHashField:
    def test_returns_estimate_sha256(self) -> None:
        obj = {"estimate_sha256": "abc123"}
        field, value = MODULE.pick_estimate_hash_field(obj)
        assert field == "estimate_sha256"
        assert value == "abc123"

    def test_fallback_to_estimate_hash(self) -> None:
        obj = {"estimate_hash": "def456"}
        field, value = MODULE.pick_estimate_hash_field(obj)
        assert field == "estimate_hash"
        assert value == "def456"

    def test_missing_both_raises(self) -> None:
        obj: dict[str, str] = {}
        try:
            MODULE.pick_estimate_hash_field(obj)
            assert False, "Should raise"
        except KeyError:
            pass


class TestValidateApproval:
    def test_valid_approval(self) -> None:
        obj = {
            "schema_version": 1,
            "issue_number": 123,
            "mode": "impl",
            "approved_at": "2026-01-01T00:00:00Z",
            "approver": "user",
            "estimate_hash": "abc123",
        }
        MODULE.validate_approval(obj, 123)

    def test_wrong_issue_number_raises(self) -> None:
        obj = {
            "schema_version": 1,
            "issue_number": 456,
            "mode": "impl",
            "approved_at": "2026-01-01T00:00:00Z",
            "approver": "user",
            "estimate_hash": "abc123",
        }
        try:
            MODULE.validate_approval(obj, 123)
            assert False, "Should raise"
        except ValueError:
            pass

    def test_missing_required_field_raises(self) -> None:
        obj = {"issue_number": 123}
        try:
            MODULE.validate_approval(obj, 123)
            assert False, "Should raise"
        except KeyError:
            pass

    def test_invalid_mode_raises(self) -> None:
        obj = {
            "schema_version": 1,
            "issue_number": 123,
            "mode": "invalid",
            "approved_at": "2026-01-01T00:00:00Z",
            "approver": "user",
            "estimate_hash": "abc123",
        }
        try:
            MODULE.validate_approval(obj, 123)
            assert False, "Should raise"
        except ValueError:
            pass
