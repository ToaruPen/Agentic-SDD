#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

COMMANDS = [
    "/sdd-init",
    "/research",
    "/create-prd",
    "/create-epic",
    "/create-issues",
    "/estimation",
    "/impl",
    "/tdd",
    "/review-cycle",
    "/final-review",
    "/sync-docs",
    "/create-pr",
    "/worktree",
]


@dataclass(frozen=True)
class Result:
    command: str
    ok: bool
    duration_ms: Optional[int]
    out_chars: int
    out_lines: int
    has_template: bool
    has_required_keys: bool
    has_fixed_format: bool
    has_evidence_paths: bool
    has_code_fence: bool
    has_triple_dash: bool
    error: Optional[str]


def _loads_json_lines(text: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        # Some OpenCode builds may print non-JSON logs; ignore them.
        if not line.startswith("{"):
            continue
        out.append(json.loads(line))
    return out


def _extract_last_text(events: List[Dict[str, Any]]) -> Optional[str]:
    last: Optional[str] = None
    for e in events:
        if e.get("type") != "text":
            continue
        part = e.get("part") or {}
        t = part.get("text")
        if isinstance(t, str):
            last = t
    return last


def _check_output(s: str) -> Tuple[bool, bool, bool, bool, bool, bool]:
    repo_root = Path(__file__).resolve().parents[1]

    lines = s.splitlines()
    expected_keys = [
        "phase:",
        "must_read:",
        "gates:",
        "stops:",
        "skills_to_load:",
        "next:",
    ]

    has_code_fence = "```" in s
    has_triple_dash = "---" in s

    has_fixed_format = (
        len(lines) == 7
        and lines[0].strip() == "[Context Pack v1]"
        and all(lines[i + 1].startswith(expected_keys[i]) for i in range(6))
    )

    has_template = lines[:1] == ["[Context Pack v1]"]
    has_required_keys = all(
        any(line.startswith(k) for line in lines) for k in expected_keys
    )

    has_evidence_paths = has_fixed_format
    if has_evidence_paths:
        for i, key in enumerate(expected_keys):
            line = lines[i + 1]

            # Require exactly one trailing evidence pointer: (...)
            if line.count("(") != 1 or line.count(")") != 1 or (not line.endswith(")")):
                has_evidence_paths = False
                break

            left = line.rfind("(")
            if left < 0:
                has_evidence_paths = False
                break

            value = line[len(key) : left].strip()
            if not value:
                has_evidence_paths = False
                break

            evidence = line[left + 1 : -1]
            if (not evidence) or (evidence.strip() != evidence):
                has_evidence_paths = False
                break
            if ":" in evidence:
                has_evidence_paths = False
                break
            if evidence.startswith(("/", "~", "\\")):
                has_evidence_paths = False
                break
            if "\\" in evidence:
                has_evidence_paths = False
                break
            if ".." in Path(evidence).parts:
                has_evidence_paths = False
                break

            p = repo_root / evidence
            if not p.is_file():
                has_evidence_paths = False
                break

    return (
        has_template,
        has_required_keys,
        has_fixed_format,
        has_evidence_paths,
        has_code_fence,
        has_triple_dash,
    )


def run_one(
    agent: str,
    model: str,
    command: str,
    timeout_s: int,
) -> Result:
    message = f"pack {command}"
    cmd = [
        "opencode",
        "run",
        "--format",
        "json",
        "--agent",
        agent,
        "-m",
        model,
        message,
    ]

    start = time.monotonic()
    try:
        proc = subprocess.run(  # noqa: S603
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return Result(
            command=command,
            ok=False,
            duration_ms=None,
            out_chars=0,
            out_lines=0,
            has_template=False,
            has_required_keys=False,
            has_fixed_format=False,
            has_evidence_paths=False,
            has_code_fence=False,
            has_triple_dash=False,
            error=f"timeout after {timeout_s}s",
        )

    wall_ms = int((time.monotonic() - start) * 1000)

    if proc.returncode != 0:
        return Result(
            command=command,
            ok=False,
            duration_ms=wall_ms,
            out_chars=0,
            out_lines=0,
            has_template=False,
            has_required_keys=False,
            has_fixed_format=False,
            has_evidence_paths=False,
            has_code_fence=False,
            has_triple_dash=False,
            error=f"opencode exited with {proc.returncode}: {proc.stderr.strip()}",
        )

    try:
        events = _loads_json_lines(proc.stdout)
    except Exception as e:  # noqa: BLE001
        return Result(
            command=command,
            ok=False,
            duration_ms=wall_ms,
            out_chars=len(proc.stdout),
            out_lines=len(proc.stdout.splitlines()),
            has_template=False,
            has_required_keys=False,
            has_fixed_format=False,
            has_evidence_paths=False,
            has_code_fence=False,
            has_triple_dash=False,
            error=f"failed to parse json events: {e}",
        )

    out = _extract_last_text(events)
    duration_ms = wall_ms
    if out is None:
        return Result(
            command=command,
            ok=False,
            duration_ms=duration_ms,
            out_chars=0,
            out_lines=0,
            has_template=False,
            has_required_keys=False,
            has_fixed_format=False,
            has_evidence_paths=False,
            has_code_fence=False,
            has_triple_dash=False,
            error="no final text output found",
        )

    (
        has_template,
        has_required_keys,
        has_fixed_format,
        has_evidence_paths,
        has_code_fence,
        has_triple_dash,
    ) = _check_output(out)
    ok = (
        has_template
        and has_required_keys
        and has_fixed_format
        and has_evidence_paths
        and (not has_code_fence)
        and (not has_triple_dash)
    )

    return Result(
        command=command,
        ok=ok,
        duration_ms=duration_ms,
        out_chars=len(out),
        out_lines=len(out.splitlines()),
        has_template=has_template,
        has_required_keys=has_required_keys,
        has_fixed_format=has_fixed_format,
        has_evidence_paths=has_evidence_paths,
        has_code_fence=has_code_fence,
        has_triple_dash=has_triple_dash,
        error=None if ok else "output does not meet constraints",
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Benchmark/validate OpenCode Agentic-SDD docs packs"
    )
    parser.add_argument(
        "--agent",
        default="sdd-docs",
        help="OpenCode agent name (primary)",
    )
    parser.add_argument(
        "--model",
        default="anthropic/claude-sonnet-4-5",
        help="Model ID to use",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="Timeout seconds per command",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Only run a specific command token (repeatable), e.g. --only /estimation",
    )
    args = parser.parse_args()

    targets = COMMANDS
    if args.only:
        only = set(args.only)
        targets = [c for c in COMMANDS if c in only]
        missing = sorted(only - set(targets))
        if missing:
            print(f"unknown --only: {', '.join(missing)}", file=sys.stderr)
            return 2

    results: List[Result] = []
    for c in targets:
        results.append(run_one(args.agent, args.model, c, args.timeout))

    print(
        "command\tok\tduration_s\tchars\tlines\ttemplate\tkeys\tfixed7\tevidence_path\tno_code_fence\tno_triple_dash"
    )
    failed = 0
    for r in results:
        dur_s = "" if r.duration_ms is None else f"{r.duration_ms / 1000:.2f}"
        print(
            "\t".join(
                [
                    r.command,
                    "OK" if r.ok else "NG",
                    dur_s,
                    str(r.out_chars),
                    str(r.out_lines),
                    "Y" if r.has_template else "N",
                    "Y" if r.has_required_keys else "N",
                    "Y" if r.has_fixed_format else "N",
                    "Y" if r.has_evidence_paths else "N",
                    "Y" if not r.has_code_fence else "N",
                    "Y" if not r.has_triple_dash else "N",
                ]
            )
        )
        if not r.ok:
            failed += 1
            if r.error:
                print(f"{r.command}: {r.error}", file=sys.stderr)

    if failed:
        print(f"{failed} command(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
