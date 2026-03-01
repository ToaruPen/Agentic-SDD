#!/usr/bin/env python3

"""Shared subprocess helpers.

`S603` is suppressed in this module because calls use trusted command arrays from
repository code (not shell strings, not user-controlled input). Keep that
invariant when adding new call sites to `run_cmd` / `check_output_cmd`.
"""

from __future__ import annotations

import os
import subprocess
from contextlib import suppress
from typing import IO, Any, Literal, NoReturn, overload


@overload
def run_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    check: bool = True,
    text: Literal[True] = True,
    capture_output: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]: ...


@overload
def run_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    check: bool = True,
    text: Literal[False],
    capture_output: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[bytes]: ...


def run_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    check: bool = True,
    text: bool = True,
    capture_output: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes]:
    return subprocess.run(  # noqa: S603
        cmd,
        cwd=cwd,
        check=check,
        text=text,
        capture_output=capture_output,
        timeout=timeout,
    )


@overload
def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | IO[Any] | None = None,
    text: Literal[True] = True,
    timeout: float | None = None,
) -> str: ...


@overload
def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | IO[Any] | None = None,
    text: Literal[False],
    timeout: float | None = None,
) -> bytes: ...


def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | IO[Any] | None = None,
    text: bool = True,
    timeout: float | None = None,
) -> str | bytes:
    return subprocess.check_output(  # noqa: S603
        cmd,
        cwd=cwd,
        stderr=stderr,
        text=text,
        timeout=timeout,
    )


def exit_with_subprocess_returncode(returncode: int) -> NoReturn:
    """Exit with subprocess return semantics, including POSIX signal propagation."""
    if returncode >= 0:
        raise SystemExit(returncode)

    signal_number = -returncode
    if os.name == "posix":
        with suppress(OSError):
            os.kill(os.getpid(), signal_number)

    raise SystemExit(128 + signal_number)
