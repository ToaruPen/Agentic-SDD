#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import argparse
import importlib.util
import json
import subprocess
import time
from dataclasses import dataclass
from typing import Any

from _lib.subprocess_utils import run_cmd

REPO_ROOT = Path(__file__).resolve().parents[2]
SUPPORTED_COMMANDS_HEADER = "Supported command tokens:"
SUPPORTED_COMMANDS_END = "Alias:"

NON_PACK_COMMAND_DOCS: set[str] = {
    "cleanup.md",
    "debug.md",
    "generate-project-config.md",
    "ui-iterate.md",
}


def _parse_supported_command_tokens(docs_text: str) -> list[str]:
    commands: list[str] = []
    in_section = False
    saw_item = False
    for raw_line in docs_text.splitlines():
        line = raw_line.strip()
        if line == SUPPORTED_COMMANDS_HEADER:
            in_section = True
            continue
        if not in_section:
            continue
        if line == SUPPORTED_COMMANDS_END:
            break
        if not line:
            if saw_item:
                break
            continue
        if not line.startswith("- /"):
            if saw_item:
                break
            continue
        token_parts = line[2:].strip().split()
        if not token_parts:
            continue
        token = token_parts[0]
        if token.startswith("/") and len(token) > 1 and token not in commands:
            commands.append(token)
            saw_item = True
    return commands


def _load_supported_commands(repo_root: Path) -> list[str]:
    docs_path = repo_root / ".agent/agents/docs.md"
    if not docs_path.is_file():
        raise RuntimeError(f"SoT file not found: {docs_path}")
    try:
        docs_text = docs_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"failed to read SoT file: {docs_path}: {exc}") from exc
    commands = _parse_supported_command_tokens(docs_text)
    if not commands:
        raise RuntimeError(
            "failed to load supported command tokens from .agent/agents/docs.md"
        )
    return commands


def _token_to_command_doc_name(command_name: str) -> str:
    if command_name == "/sdd-init":
        return "init.md"
    return f"{command_name.lstrip('/')}.md"


def _command_doc_coverage(
    repo_root: Path, supported_tokens: list[str]
) -> tuple[list[str], list[str]]:
    commands_dir = repo_root / ".agent/commands"
    doc_names = sorted(p.name for p in commands_dir.glob("*.md") if p.is_file())
    supported_doc_names = {
        _token_to_command_doc_name(command_name) for command_name in supported_tokens
    }

    missing = sorted(name for name in supported_doc_names if name not in doc_names)
    uncovered = sorted(
        name
        for name in doc_names
        if name not in supported_doc_names and name not in NON_PACK_COMMAND_DOCS
    )
    return missing, uncovered


_COMMANDS: list[str] | None = None


def _load_contract_module() -> Any:
    module_path = REPO_ROOT / "scripts" / "_lib" / "context_pack_contract.py"
    module_name = "context_pack_contract"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


_CONTRACT: Any = None


def get_commands() -> list[str]:
    commands = _COMMANDS
    if commands is None:
        commands = _load_supported_commands(REPO_ROOT)
        globals()["_COMMANDS"] = commands
    return commands


def get_contract() -> Any:
    contract = _CONTRACT
    if contract is None:
        mod = _load_contract_module()
        contract = mod.load_context_pack_contract(REPO_ROOT)
        globals()["_CONTRACT"] = contract
    return contract


def __getattr__(name: str) -> Any:
    """Lazy module-level access for COMMANDS and CONTRACT (backward compat)."""
    if name == "COMMANDS":
        return get_commands()
    if name == "CONTRACT":
        return get_contract()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


@dataclass(frozen=True)
class Result:
    command: str
    ok: bool
    duration_ms: int | None
    out_chars: int
    out_lines: int
    has_template: bool
    has_required_keys: bool
    has_fixed_format: bool
    has_evidence_paths: bool
    has_code_fence: bool
    has_triple_dash: bool
    error: str | None


def _loads_json_lines(text: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for raw_line in text.splitlines():
        stripped_line = raw_line.strip()
        if not stripped_line:
            continue
        # Some OpenCode builds may print non-JSON logs; ignore them.
        if not stripped_line.startswith("{"):
            continue
        out.append(json.loads(stripped_line))
    return out


def _extract_last_text(events: list[dict[str, Any]]) -> str | None:
    last: str | None = None
    for e in events:
        if e.get("type") != "text":
            continue
        part = e.get("part") or {}
        t = part.get("text")
        if isinstance(t, str):
            last = t
    return last


def _check_output(s: str) -> tuple[bool, bool, bool, bool, bool, bool]:
    contract = get_contract()

    lines = s.splitlines()
    expected_keys = list(contract.keys)

    has_code_fence = contract.forbidden_markers[0] in s
    has_triple_dash = contract.forbidden_markers[1] in s

    has_fixed_format = (
        len(lines) == contract.line_count
        and lines[0].strip() == contract.header
        and all(
            lines[i + 1].startswith(expected_keys[i]) for i in range(len(expected_keys))
        )
    )

    has_template = lines[:1] == [contract.header]
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

            p = REPO_ROOT / evidence
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
        proc = run_cmd(cmd, check=False, timeout=timeout_s)
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
    except json.JSONDecodeError as exc:
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
            error=f"failed to parse json events: {exc}",
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
    if args.timeout <= 0:
        parser.error("timeout must be a positive integer")

    commands = get_commands()
    missing_docs, uncovered_docs = _command_doc_coverage(REPO_ROOT, commands)
    if missing_docs:
        print(
            "missing command docs for supported Context Pack tokens: "
            f"{', '.join(missing_docs)}",
            file=sys.stderr,
        )
        return 2
    if uncovered_docs:
        print(
            "unclassified command docs found (add to Context Pack tokens or "
            f"NON_PACK_COMMAND_DOCS): {', '.join(uncovered_docs)}",
            file=sys.stderr,
        )
        return 2

    targets = commands
    if args.only:
        only = set(args.only)
        targets = [c for c in commands if c in only]
        missing = sorted(only - set(targets))
        if missing:
            print(f"unknown --only: {', '.join(missing)}", file=sys.stderr)
            return 2

    results = [run_one(args.agent, args.model, c, args.timeout) for c in targets]

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
