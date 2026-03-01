from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "_lib" / "subprocess_utils.py"
    spec = importlib.util.spec_from_file_location("subprocess_utils", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_run_cmd_success_text_true_returns_completed_process_str() -> None:
    result = MODULE.run_cmd([sys.executable, "-c", 'print("hello", end="")'], text=True)

    assert result.returncode == 0
    assert result.stdout == "hello"
    assert isinstance(result.stdout, str)


def test_run_cmd_success_text_false_returns_completed_process_bytes() -> None:
    result = MODULE.run_cmd(
        [sys.executable, "-c", 'print("hello", end="")'], text=False
    )

    assert result.returncode == 0
    assert result.stdout == b"hello"
    assert isinstance(result.stdout, bytes)


def test_run_cmd_check_true_raises_called_process_error() -> None:
    with pytest.raises(subprocess.CalledProcessError):
        MODULE.run_cmd([sys.executable, "-c", "import sys; sys.exit(1)"], check=True)


def test_run_cmd_check_false_returns_non_zero_completed_process() -> None:
    result = MODULE.run_cmd(
        [sys.executable, "-c", "import sys; sys.exit(1)"], check=False
    )

    assert result.returncode != 0


def test_run_cmd_timeout_raises_timeout_expired() -> None:
    with pytest.raises(subprocess.TimeoutExpired):
        MODULE.run_cmd(
            [sys.executable, "-c", "import time; time.sleep(1)"],
            timeout=0.01,
        )


def test_check_output_cmd_success_text_true_returns_str() -> None:
    output = MODULE.check_output_cmd([sys.executable, "-c", 'print("hello", end="")'])

    assert output == "hello"
    assert isinstance(output, str)


def test_check_output_cmd_success_text_false_returns_bytes() -> None:
    output = MODULE.check_output_cmd(
        [sys.executable, "-c", 'print("hello", end="")'],
        text=False,
    )

    assert output == b"hello"
    assert isinstance(output, bytes)


def test_check_output_cmd_failure_raises_called_process_error() -> None:
    with pytest.raises(subprocess.CalledProcessError):
        MODULE.check_output_cmd([sys.executable, "-c", "import sys; sys.exit(1)"])


def test_check_output_cmd_accepts_stderr_parameter() -> None:
    output = MODULE.check_output_cmd(
        [
            sys.executable,
            "-c",
            'import sys; print("hello", end=""); print("err", file=sys.stderr)',
        ],
        stderr=subprocess.DEVNULL,
    )

    assert output == "hello"


def test_run_cmd_passes_expected_kwargs_with_mock(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}

    def _fake_run(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        captured["args"] = args
        captured["kwargs"] = kwargs
        return subprocess.CompletedProcess([sys.executable], 0, stdout="ok", stderr="")

    monkeypatch.setattr(MODULE.subprocess, "run", _fake_run)
    result = MODULE.run_cmd(
        [sys.executable, "-c", "print('x')"],
        cwd=".",
        check=False,
        text=True,
        capture_output=True,
        timeout=3,
    )
    assert result.stdout == "ok"
    assert captured["kwargs"] == {
        "cwd": ".",
        "check": False,
        "text": True,
        "capture_output": True,
        "timeout": 3,
    }


def test_run_cmd_timeout_is_propagated(monkeypatch: pytest.MonkeyPatch) -> None:
    def _fake_run(
        *_args: object, **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        raise subprocess.TimeoutExpired(cmd=[sys.executable], timeout=1)

    monkeypatch.setattr(MODULE.subprocess, "run", _fake_run)
    with pytest.raises(subprocess.TimeoutExpired):
        MODULE.run_cmd([sys.executable, "-c", "print('x')"], timeout=1)


def test_check_output_cmd_passes_expected_kwargs_with_mock(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}

    def _fake_check_output(*args: object, **kwargs: object) -> str:
        captured["args"] = args
        captured["kwargs"] = kwargs
        return "ok"

    monkeypatch.setattr(MODULE.subprocess, "check_output", _fake_check_output)
    result = MODULE.check_output_cmd(
        [sys.executable, "-c", "print('x')"],
        cwd=".",
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=4,
    )
    assert result == "ok"
    assert captured["kwargs"] == {
        "cwd": ".",
        "stderr": subprocess.DEVNULL,
        "text": True,
        "timeout": 4,
    }


def test_check_output_cmd_timeout_is_propagated(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def _fake_check_output(*_args: object, **_kwargs: object) -> str:
        raise subprocess.TimeoutExpired(cmd=[sys.executable], timeout=1)

    monkeypatch.setattr(MODULE.subprocess, "check_output", _fake_check_output)
    with pytest.raises(subprocess.TimeoutExpired):
        MODULE.check_output_cmd([sys.executable, "-c", "print('x')"], timeout=1)


def test_exit_with_subprocess_returncode_nonzero() -> None:
    with pytest.raises(SystemExit) as excinfo:
        MODULE.exit_with_subprocess_returncode(3)

    assert excinfo.value.code == 3


def test_exit_with_subprocess_returncode_zero() -> None:
    with pytest.raises(SystemExit) as excinfo:
        MODULE.exit_with_subprocess_returncode(0)

    assert excinfo.value.code == 0


def test_exit_with_subprocess_returncode_signal_uses_exit_code(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[tuple[int, int]] = []

    monkeypatch.setattr(MODULE.os, "kill", lambda pid, sig: calls.append((pid, sig)))

    with pytest.raises(SystemExit) as excinfo:
        MODULE.exit_with_subprocess_returncode(-9)

    assert calls == [(MODULE.os.getpid(), 9)]
    assert excinfo.value.code == 137


def test_exit_with_subprocess_returncode_signal_fallback_when_kill_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def _fail(_: int, __: int) -> None:
        raise OSError(1, "boom")

    monkeypatch.setattr(MODULE.os, "kill", _fail)

    with pytest.raises(SystemExit) as excinfo:
        MODULE.exit_with_subprocess_returncode(-15)

    assert excinfo.value.code == 143
