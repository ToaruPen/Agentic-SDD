#!/usr/bin/env python3

from __future__ import annotations

import subprocess
from typing import Literal, overload


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
    stderr: int | None = None,
    text: Literal[True] = True,
    timeout: float | None = None,
) -> str: ...


@overload
def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | None = None,
    text: Literal[False],
    timeout: float | None = None,
) -> bytes: ...


def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | None = None,
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
