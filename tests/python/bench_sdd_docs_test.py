from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

pytest = importlib.import_module("pytest")


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


def test_commands_loaded_from_docs_are_non_empty(bench_module: ModuleType) -> None:
    assert bench_module.COMMANDS
    for command in bench_module.COMMANDS:
        assert isinstance(command, str)
        assert command.startswith("/")


def test_commands_include_core_flow_tokens(bench_module: ModuleType) -> None:
    # Core workflow guard: keep these tokens explicit to catch accidental removal.
    for token in [
        "/sdd-init",
        "/research",
        "/estimation",
        "/impl",
        "/tdd",
        "/test-review",
        "/review-cycle",
        "/final-review",
        "/create-pr",
        "/pr-bots-review",
    ]:
        assert token in bench_module.COMMANDS


def test_parse_supported_command_tokens_empty_returns_empty(
    bench_module: ModuleType,
) -> None:
    result = bench_module._parse_supported_command_tokens("")
    assert result == []


def test_parse_supported_command_tokens_no_header_returns_empty(
    bench_module: ModuleType,
) -> None:
    result = bench_module._parse_supported_command_tokens("- /foo\n- /bar")
    assert result == []


def test_command_docs_are_classified(bench_module: ModuleType) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    missing, uncovered = bench_module._command_doc_coverage(
        repo_root,
        bench_module.COMMANDS,
    )
    assert missing == []
    assert uncovered == []


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
