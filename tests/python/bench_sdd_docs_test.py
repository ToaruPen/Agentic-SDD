from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Generator

pytest = importlib.import_module("pytest")


EXPECTED_COMMANDS = [
    "/sdd-init",
    "/create-prd",
    "/create-epic",
    "/create-issues",
    "/estimation",
    "/impl",
    "/tdd",
    "/test-review",
    "/review-cycle",
    "/final-review",
    "/sync-docs",
    "/create-pr",
    "/pr-bots-review",
    "/worktree",
    "/research",
]


@pytest.fixture(scope="module")
def bench_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "bench-sdd-docs.py"
    spec = importlib.util.spec_from_file_location("bench_sdd_docs", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def contract_module() -> Generator[ModuleType, None, None]:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "context_pack_contract.py"
    module_name = "context_pack_contract"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    try:
        yield module
    finally:
        sys.modules.pop(module_name, None)


@pytest.mark.parametrize("command", EXPECTED_COMMANDS)
def test_commands_include_expected_set(bench_module: ModuleType, command: str) -> None:
    assert command in bench_module.COMMANDS


def test_contract_loader_returns_v1_shape(contract_module: ModuleType) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    contract = contract_module.load_context_pack_contract(repo_root)
    assert contract.header == "[Context Pack v1]"
    assert contract.keys == (
        "phase:",
        "must_read:",
        "gates:",
        "stops:",
        "skills_to_load:",
        "next:",
    )
    assert contract.line_count == 7
    assert contract.forbidden_markers == ("```", "---")


def test_bench_uses_shared_contract(
    bench_module: ModuleType, contract_module: ModuleType
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    contract = contract_module.load_context_pack_contract(repo_root)
    assert bench_module.CONTRACT.header == contract.header
    assert bench_module.CONTRACT.keys == contract.keys
    assert bench_module.CONTRACT.line_count == contract.line_count
    assert bench_module.CONTRACT.forbidden_markers == contract.forbidden_markers


def test_check_output_accepts_research_pack(bench_module: ModuleType) -> None:
    output = "\n".join(
        [
            "[Context Pack v1]",
            "phase: estimation prep (.agent/commands/research.md)",
            "must_read: /research epic contract (.agent/commands/research.md)",
            "gates: required candidate fields (.agent/commands/research.md)",
            "stops: fail-fast on missing evidence links (.agent/commands/research.md)",
            "skills_to_load: none (.agent/commands/research.md)",
            "next: run /estimation after research (.agent/commands/research.md)",
        ]
    )
    (
        has_template,
        has_required_keys,
        has_fixed_format,
        has_evidence_paths,
        has_code_fence,
        has_triple_dash,
    ) = bench_module._check_output(output)

    assert has_template
    assert has_required_keys
    assert has_fixed_format
    assert has_evidence_paths
    assert not has_code_fence
    assert not has_triple_dash
