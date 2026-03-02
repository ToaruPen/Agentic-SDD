from __future__ import annotations

import importlib.util
import io
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "gates" / "check_impl_gate.py"
    spec = importlib.util.spec_from_file_location("check_impl_gate", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_read_stdin_json_empty_and_invalid(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(MODULE.sys, "stdin", io.StringIO("   "))
    assert MODULE.read_stdin_json() == {}

    monkeypatch.setattr(MODULE.sys, "stdin", io.StringIO("{invalid"))
    assert MODULE.read_stdin_json() == {}

    monkeypatch.setattr(MODULE.sys, "stdin", io.StringIO("[1,2,3]"))
    assert MODULE.read_stdin_json() == {}


def test_extract_path_variants() -> None:
    assert MODULE.extract_path({"tool_input": {"path": "a.txt"}}) == "a.txt"
    assert MODULE.extract_path({"input": {"filePath": "b.txt"}}) == "b.txt"
    assert MODULE.extract_path({"args": {"filename": "c.txt"}}) == "c.txt"
    assert MODULE.extract_path({"parameters": {"target": "d.txt"}}) == "d.txt"
    assert MODULE.extract_path({"path": "e.txt"}) == "e.txt"
    assert MODULE.extract_path({}) is None


def test_is_agentic_sdd_local_path_boundaries() -> None:
    assert MODULE.is_agentic_sdd_local_path(".agentic-sdd")
    assert MODULE.is_agentic_sdd_local_path(".agentic-sdd/approvals/x.json")
    assert MODULE.is_agentic_sdd_local_path(".agentic-sdd\\approvals\\x.json")
    assert not MODULE.is_agentic_sdd_local_path("agentic-sdd/file")
    assert not MODULE.is_agentic_sdd_local_path("foo/.agentic-sdd/file")


def test_main_returns_zero_when_repo_root_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(MODULE, "read_stdin_json", dict)
    monkeypatch.setattr(MODULE, "extract_path", lambda _obj: None)
    monkeypatch.setattr(MODULE, "repo_root", lambda: None)
    assert MODULE.main() == 0


def test_main_worktree_gate_failure_forwards_output(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    worktree = tmp_path / "scripts" / "gates" / "validate_worktree.py"
    worktree.parent.mkdir(parents=True, exist_ok=True)
    worktree.write_text("", encoding="utf-8")

    monkeypatch.setattr(MODULE, "read_stdin_json", dict)
    monkeypatch.setattr(MODULE, "extract_path", lambda _obj: None)
    monkeypatch.setattr(MODULE, "repo_root", lambda: str(tmp_path))
    monkeypatch.setattr(
        MODULE,
        "run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=2, stdout="WOUT", stderr="WERR"
        ),
    )

    assert MODULE.main() == 2
    captured = capsys.readouterr()
    assert "WOUT" in captured.out
    assert "WERR" in captured.err


def test_main_local_agentic_path_skips_approval_gate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    worktree = tmp_path / "scripts" / "gates" / "validate_worktree.py"
    worktree.parent.mkdir(parents=True, exist_ok=True)
    worktree.write_text("", encoding="utf-8")
    approval = tmp_path / "scripts" / "gates" / "validate_approval.py"
    approval.write_text("", encoding="utf-8")

    calls: list[list[str]] = []

    def _run(cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(cmd)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(MODULE, "read_stdin_json", lambda: {"path": ".agentic-sdd/x"})
    monkeypatch.setattr(MODULE, "extract_path", lambda _obj: ".agentic-sdd/x")
    monkeypatch.setattr(MODULE, "repo_root", lambda: str(tmp_path))
    monkeypatch.setattr(MODULE, "run", _run)

    assert MODULE.main() == 0
    assert len(calls) == 1


def test_main_runs_approval_gate_and_propagates_its_returncode(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    worktree = tmp_path / "scripts" / "gates" / "validate_worktree.py"
    worktree.parent.mkdir(parents=True, exist_ok=True)
    worktree.write_text("", encoding="utf-8")
    approval = tmp_path / "scripts" / "gates" / "validate_approval.py"
    approval.write_text("", encoding="utf-8")

    calls = 0

    def _run(_cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        nonlocal calls
        calls += 1
        if calls == 1:
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        return SimpleNamespace(returncode=3, stdout="AOUT", stderr="AERR")

    monkeypatch.setattr(MODULE, "read_stdin_json", lambda: {"path": "src/x.py"})
    monkeypatch.setattr(MODULE, "extract_path", lambda _obj: "src/x.py")
    monkeypatch.setattr(MODULE, "repo_root", lambda: str(tmp_path))
    monkeypatch.setattr(MODULE, "run", _run)

    assert MODULE.main() == 3


def test_main_returns_one_when_run_raises_oserror(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    worktree = tmp_path / "scripts" / "gates" / "validate_worktree.py"
    worktree.parent.mkdir(parents=True, exist_ok=True)
    worktree.write_text("", encoding="utf-8")

    monkeypatch.setattr(MODULE, "read_stdin_json", dict)
    monkeypatch.setattr(MODULE, "extract_path", lambda _obj: None)
    monkeypatch.setattr(MODULE, "repo_root", lambda: str(tmp_path))

    def _raise(*_args: object, **_kwargs: object) -> SimpleNamespace:
        raise OSError("boom")

    monkeypatch.setattr(MODULE, "run", _raise)
    assert MODULE.main() == 1
