from __future__ import annotations

import importlib.util
import subprocess
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
    result = MODULE.run_cmd(["python3", "-c", 'print("hello", end="")'], text=True)

    assert result.returncode == 0
    assert result.stdout == "hello"
    assert isinstance(result.stdout, str)


def test_run_cmd_success_text_false_returns_completed_process_bytes() -> None:
    result = MODULE.run_cmd(["python3", "-c", 'print("hello", end="")'], text=False)

    assert result.returncode == 0
    assert result.stdout == b"hello"
    assert isinstance(result.stdout, bytes)


def test_run_cmd_check_true_raises_called_process_error() -> None:
    with pytest.raises(subprocess.CalledProcessError):
        MODULE.run_cmd(["false"], check=True)


def test_run_cmd_check_false_returns_non_zero_completed_process() -> None:
    result = MODULE.run_cmd(["false"], check=False)

    assert result.returncode != 0


def test_run_cmd_timeout_raises_timeout_expired() -> None:
    with pytest.raises(subprocess.TimeoutExpired):
        MODULE.run_cmd(
            ["python3", "-c", "import time; time.sleep(1)"],
            timeout=0.01,
        )


def test_check_output_cmd_success_text_true_returns_str() -> None:
    output = MODULE.check_output_cmd(["python3", "-c", 'print("hello", end="")'])

    assert output == "hello"
    assert isinstance(output, str)


def test_check_output_cmd_success_text_false_returns_bytes() -> None:
    output = MODULE.check_output_cmd(
        ["python3", "-c", 'print("hello", end="")'],
        text=False,
    )

    assert output == b"hello"
    assert isinstance(output, bytes)


def test_check_output_cmd_failure_raises_called_process_error() -> None:
    with pytest.raises(subprocess.CalledProcessError):
        MODULE.check_output_cmd(["false"])


def test_check_output_cmd_accepts_stderr_parameter() -> None:
    output = MODULE.check_output_cmd(
        [
            "python3",
            "-c",
            'import sys; print("hello", end=""); print("err", file=sys.stderr)',
        ],
        stderr=subprocess.DEVNULL,
    )

    assert output == "hello"
