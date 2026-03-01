#!/usr/bin/env python3

import subprocess


def run_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    check: bool = True,
    text: bool = True,
    capture_output: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        cmd,
        cwd=cwd,
        check=check,
        text=text,
        capture_output=capture_output,
        timeout=timeout,
    )


def check_output_cmd(
    cmd: list[str],
    *,
    cwd: str | None = None,
    stderr: int | None = None,
    text: bool = True,
    timeout: float | None = None,
) -> str:
    return subprocess.check_output(  # noqa: S603
        cmd,
        cwd=cwd,
        stderr=stderr,
        text=text,
        timeout=timeout,
    )
