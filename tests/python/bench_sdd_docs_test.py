from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "bench-sdd-docs.py"
    spec = importlib.util.spec_from_file_location("bench_sdd_docs", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_commands_include_test_review() -> None:
    module = load_module()
    assert "/test-review" in module.COMMANDS


def test_commands_include_pr_bots_review() -> None:
    module = load_module()
    assert "/pr-bots-review" in module.COMMANDS


def test_commands_include_research() -> None:
    module = load_module()
    assert "/research" in module.COMMANDS


def test_check_output_accepts_research_pack() -> None:
    module = load_module()
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
    ) = module._check_output(output)

    assert has_template
    assert has_required_keys
    assert has_fixed_format
    assert has_evidence_paths
    assert not has_code_fence
    assert not has_triple_dash
