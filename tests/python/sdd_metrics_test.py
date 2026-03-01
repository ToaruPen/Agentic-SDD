"""Tests for scripts/sdd-metrics.py."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any, Dict

import pytest


def _load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "sdd-metrics.py"
    spec = importlib.util.spec_from_file_location("sdd_metrics", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = _load_module()


# ---------------------------------------------------------------------------
# Mode detection
# ---------------------------------------------------------------------------


class TestDetectMode:
    def test_context_pack_present(self, tmp_path: Path) -> None:
        agent_dir = tmp_path / ".agent" / "agents"
        agent_dir.mkdir(parents=True)
        (agent_dir / "docs.md").write_text("[Context Pack v1]\nfoo: bar\n")
        assert M._detect_mode(tmp_path) == "context-pack"

    def test_docs_missing(self, tmp_path: Path) -> None:
        assert M._detect_mode(tmp_path) == "full-docs"

    def test_docs_without_header(self, tmp_path: Path) -> None:
        agent_dir = tmp_path / ".agent" / "agents"
        agent_dir.mkdir(parents=True)
        (agent_dir / "docs.md").write_text("# No context pack here\n")
        assert M._detect_mode(tmp_path) == "full-docs"

    def test_env_var_overrides_file(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """SDD_METRICS_MODE env var takes precedence over file-based detection."""
        agent_dir = tmp_path / ".agent" / "agents"
        agent_dir.mkdir(parents=True)
        (agent_dir / "docs.md").write_text("[Context Pack v1]\nfoo: bar\n")
        # File says context-pack, but env says full-docs
        monkeypatch.setenv("SDD_METRICS_MODE", "full-docs")
        assert M._detect_mode(tmp_path) == "full-docs"

    def test_env_var_context_pack(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """SDD_METRICS_MODE=context-pack is respected even without docs.md."""
        monkeypatch.setenv("SDD_METRICS_MODE", "context-pack")
        assert M._detect_mode(tmp_path) == "context-pack"

    def test_env_var_invalid_ignored(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Invalid SDD_METRICS_MODE values fall through to file-based detection."""
        monkeypatch.setenv("SDD_METRICS_MODE", "invalid-value")
        # No docs.md → falls through to full-docs
        assert M._detect_mode(tmp_path) == "full-docs"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


class TestSafeInt:
    def test_valid(self) -> None:
        assert M._safe_int(42) == 42
        assert M._safe_int("123") == 123

    def test_none(self) -> None:
        assert M._safe_int(None) is None

    def test_invalid(self) -> None:
        assert M._safe_int("abc") is None


class TestReadMetadata:
    def test_valid_json(self, tmp_path: Path) -> None:
        f = tmp_path / "meta.json"
        f.write_text('{"key": "value"}')
        assert M._read_metadata(f) == {"key": "value"}

    def test_missing_file(self, tmp_path: Path) -> None:
        assert M._read_metadata(tmp_path / "missing.json") == {}

    def test_invalid_json(self, tmp_path: Path) -> None:
        f = tmp_path / "bad.json"
        f.write_text("not json")
        assert M._read_metadata(f) == {}


# ---------------------------------------------------------------------------
# record subcommand
# ---------------------------------------------------------------------------


def _make_metadata(tmp_path: Path, data: Dict[str, Any]) -> Path:
    meta = tmp_path / "review-metadata.json"
    meta.write_text(json.dumps(data))
    return meta


def _make_args(**kwargs: Any) -> Any:
    """Build a namespace matching cmd_record expectations."""
    import argparse

    defaults = {
        "repo_root": "",
        "command": "review-cycle",
        "scope_id": "issue-99",
        "run_id": "20260301_140000",
        "metadata_file": None,
        "mode": "auto",
        "status": None,
    }
    defaults.update(kwargs)
    return argparse.Namespace(**defaults)


class TestCmdRecord:
    def test_record_creates_file(self, tmp_path: Path) -> None:
        meta = _make_metadata(
            tmp_path,
            {
                "prompt_bytes": 5000,
                "sot_bytes": 2000,
                "diff_bytes": 3000,
                "engine_runtime_ms": 12000,
                "head_sha": "abc123",
                "base_ref": "main",
                "cache_policy": "balanced",
                "reused": False,
                "review_engine": "codex",
            },
        )
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(meta),
            mode="context-pack",
        )
        result = M.cmd_record(args)
        assert result == 0

        out = (
            tmp_path
            / ".agentic-sdd"
            / "metrics"
            / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        assert out.is_file()
        data = json.loads(out.read_text())
        assert data["schema_version"] == 1
        assert data["command"] == "review-cycle"
        assert data["mode"] == "context-pack"
        assert data["prompt_bytes"] == 5000
        assert data["tokens_approx"] == 1250  # 5000 // 4
        assert data["error_reason"] is None

    def test_record_missing_metadata(self, tmp_path: Path) -> None:
        """AC1: failure reason is recorded when metadata is unreadable."""
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(tmp_path / "nonexistent.json"),
            mode="full-docs",
        )
        result = M.cmd_record(args)
        assert result == 0

        out = (
            tmp_path
            / ".agentic-sdd"
            / "metrics"
            / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        data = json.loads(out.read_text())
        assert data["error_reason"] is not None
        assert "missing or unreadable" in data["error_reason"]

    def test_record_auto_mode_detection(self, tmp_path: Path) -> None:
        """AC2: mode=auto detects context-pack correctly."""
        agent_dir = tmp_path / ".agent" / "agents"
        agent_dir.mkdir(parents=True)
        (agent_dir / "docs.md").write_text("[Context Pack v1]\nfoo: bar\n")
        meta = _make_metadata(tmp_path, {"head_sha": "x"})
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(meta),
            mode="auto",
        )
        M.cmd_record(args)
        out = (
            tmp_path
            / ".agentic-sdd"
            / "metrics"
            / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        data = json.loads(out.read_text())
        assert data["mode"] == "context-pack"

    def test_record_tokens_from_sot_and_diff(self, tmp_path: Path) -> None:
        """When prompt_bytes is absent, tokens_approx is computed from sot+diff."""
        meta = _make_metadata(tmp_path, {"sot_bytes": 1000, "diff_bytes": 600})
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(meta),
            mode="full-docs",
        )
        M.cmd_record(args)
        out = (
            tmp_path
            / ".agentic-sdd"
            / "metrics"
            / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        data = json.loads(out.read_text())
        assert data["total_bytes"] == 1600
        assert data["tokens_approx"] == 400  # 1600 // 4

    def test_record_invalid_command(self, tmp_path: Path) -> None:
        args = _make_args(repo_root=str(tmp_path), command="bad-cmd")
        result = M.cmd_record(args)
        assert result == 2

    def test_record_without_metadata_file(self, tmp_path: Path) -> None:
        """create-pr path: no metadata file, record still succeeds with null byte fields."""
        args = _make_args(
            repo_root=str(tmp_path),
            command="create-pr",
            mode="context-pack",
            metadata_file=None,
        )
        result = M.cmd_record(args)
        assert result == 0

        out = (
            tmp_path
            / ".agentic-sdd"
            / "metrics"
            / "issue-99"
            / "20260301_140000-create-pr.json"
        )
        assert out.is_file()
        data = json.loads(out.read_text())
        assert data["command"] == "create-pr"
        assert data["prompt_bytes"] is None
        assert data["tokens_approx"] is None
        assert data["error_reason"] is None

    def test_record_status_from_cli_arg(self, tmp_path: Path) -> None:
        """Explicit --status takes precedence over metadata."""
        meta = _make_metadata(tmp_path, {"status": "Blocked"})
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(meta),
            mode="full-docs",
            status="Approved",
        )
        M.cmd_record(args)
        out = (
            tmp_path / ".agentic-sdd" / "metrics" / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        data = json.loads(out.read_text())
        assert data["status"] == "Approved"

    def test_record_status_from_metadata(self, tmp_path: Path) -> None:
        """When --status is not set, status is extracted from metadata."""
        meta = _make_metadata(tmp_path, {"status": "Blocked", "prompt_bytes": 100})
        args = _make_args(
            repo_root=str(tmp_path),
            metadata_file=str(meta),
            mode="full-docs",
        )
        M.cmd_record(args)
        out = (
            tmp_path / ".agentic-sdd" / "metrics" / "issue-99"
            / "20260301_140000-review-cycle.json"
        )
        data = json.loads(out.read_text())
        assert data["status"] == "Blocked"


# ---------------------------------------------------------------------------
# aggregate subcommand
# ---------------------------------------------------------------------------


def _write_metric(
    tmp_path: Path,
    scope_id: str,
    run_id: str,
    command: str,
    mode: str,
    tokens: int | None,
    prompt_bytes: int | None = None,
    engine_runtime_ms: int | None = None,
) -> None:
    d = tmp_path / ".agentic-sdd" / "metrics" / scope_id
    d.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "command": command,
        "mode": mode,
        "tokens_approx": tokens,
        "prompt_bytes": prompt_bytes,
        "engine_runtime_ms": engine_runtime_ms,
    }
    (d / f"{run_id}-{command}.json").write_text(json.dumps(payload))


class TestCmdAggregate:
    def test_empty(self, tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
        import argparse

        args = argparse.Namespace(repo_root=str(tmp_path), scope_id=None)
        result = M.cmd_aggregate(args)
        assert result == 0

    def test_groups_by_mode(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        import argparse

        _write_metric(
            tmp_path, "issue-1", "r1", "review-cycle", "context-pack", 100, 400, 5000
        )
        _write_metric(
            tmp_path, "issue-1", "r2", "review-cycle", "context-pack", 200, 800, 6000
        )
        _write_metric(
            tmp_path, "issue-1", "r3", "review-cycle", "full-docs", 500, 2000, 10000
        )

        args = argparse.Namespace(repo_root=str(tmp_path), scope_id="issue-1")
        result = M.cmd_aggregate(args)
        assert result == 0

        out = capsys.readouterr().out
        lines = out.strip().split("\n")
        assert len(lines) == 3  # header + 2 modes
        assert "context-pack" in lines[1]
        assert "full-docs" in lines[2]


# ---------------------------------------------------------------------------
# report subcommand
# ---------------------------------------------------------------------------


class TestCmdReport:
    def test_report_output(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        """AC3/AC4: cumulative comparison is generated and is reproducible."""
        import argparse

        _write_metric(
            tmp_path, "issue-1", "r1", "review-cycle", "context-pack", 100, 400
        )
        _write_metric(tmp_path, "issue-1", "r2", "review-cycle", "full-docs", 500, 2000)

        args = argparse.Namespace(repo_root=str(tmp_path), scope_id="issue-1", scale=10)
        result = M.cmd_report(args)
        assert result == 0

        out = capsys.readouterr().out
        assert "Plan B Metrics Report" in out
        assert "full-docs" in out
        assert "context-pack" in out
        assert "10x runs" in out

        # AC4: re-run produces identical format
        args2 = argparse.Namespace(
            repo_root=str(tmp_path), scope_id="issue-1", scale=10
        )
        M.cmd_report(args2)
        out2 = capsys.readouterr().out
        # Structure should match (timestamps in data files are fixed)
        assert out.count("\n") == out2.count("\n")

    def test_report_100x_scale(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        import argparse

        _write_metric(tmp_path, "issue-1", "r1", "review-cycle", "context-pack", 100)
        _write_metric(tmp_path, "issue-1", "r2", "review-cycle", "full-docs", 500)

        args = argparse.Namespace(repo_root=str(tmp_path), scope_id=None, scale=100)
        result = M.cmd_report(args)
        assert result == 0

        out = capsys.readouterr().out
        assert "100x runs" in out
