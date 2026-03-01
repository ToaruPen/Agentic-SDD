from __future__ import annotations

# ruff: noqa: S101, S603
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "lint-setup.py"
    spec = importlib.util.spec_from_file_location("lint_setup", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()
REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "lint-setup.py"
REGISTRY_PATH = REPO_ROOT / "scripts" / "lint-registry.json"
TEMPLATE_DIR = REPO_ROOT / "templates" / "project-config"


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    write_file(path, json.dumps(payload, ensure_ascii=False, indent=2))


def load_real_registry() -> dict[str, Any]:
    return MODULE.load_registry(REGISTRY_PATH)


def minimal_registry() -> dict[str, Any]:
    return {
        "languages": {
            "python": {
                "linter": {
                    "name": "ruff",
                    "docs_url": "https://docs.astral.sh/ruff/rules/",
                    "essential_rules": ["E4", "F"],
                    "ci_command": "ruff check .",
                },
                "formatter": {
                    "name": "ruff format",
                    "docs_url": "https://docs.astral.sh/ruff/formatter/",
                    "conflict_rules": ["ISC001"],
                    "ci_command": "ruff format --check .",
                },
                "type_checker": {
                    "name": "mypy",
                    "docs_url": "https://mypy.readthedocs.io/",
                    "ci_command": "mypy .",
                },
            },
            "javascript": {
                "linter": {
                    "name": "eslint",
                    "docs_url": "https://eslint.org/docs/latest/rules/",
                    "essential_rules": ["eslint:recommended"],
                    "ci_command": "npx eslint .",
                },
                "formatter": {
                    "name": "prettier",
                    "docs_url": "https://prettier.io/docs/",
                    "conflict_rules": [],
                    "ci_command": "npx prettier --check .",
                },
                "type_checker": {
                    "name": None,
                    "docs_url": None,
                    "ci_command": None,
                },
            },
            "typescript": {
                "linter": {
                    "name": "eslint",
                    "docs_url": "https://eslint.org/docs/latest/rules/",
                    "essential_rules": ["eslint:recommended"],
                    "ci_command": "npx eslint .",
                },
                "formatter": {
                    "name": "prettier",
                    "docs_url": "https://prettier.io/docs/",
                    "conflict_rules": [],
                    "ci_command": "npx prettier --check .",
                },
                "type_checker": {
                    "name": "tsc",
                    "docs_url": "https://www.typescriptlang.org/tsconfig/",
                    "ci_command": "npx tsc --noEmit",
                },
            },
        }
    }


def ensure_jinja2_available(tmp_path: Path) -> Path | None:
    spec = importlib.util.find_spec("jinja2")
    if spec is not None and spec.origin is not None:
        if "site-packages" in spec.origin or "dist-packages" in spec.origin:
            return None
    package_dir = tmp_path / "jinja2"
    shim = """
from __future__ import annotations

import json
from pathlib import Path


class FileSystemLoader:
    def __init__(self, searchpath: str) -> None:
        self.searchpath = searchpath


class _Template:
    def __init__(self, content: str) -> None:
        self.content = content

    def render(self, **context: object) -> str:
        return self.content + "\\n" + json.dumps(context, ensure_ascii=False)


class Environment:
    def __init__(self, loader: FileSystemLoader, **_kwargs: object) -> None:
        self.loader = loader

    def get_template(self, name: str) -> _Template:
        template_path = Path(self.loader.searchpath) / name
        return _Template(template_path.read_text(encoding="utf-8"))
""".strip()
    write_file(package_dir / "__init__.py", shim)
    shim_root = package_dir.parent
    shim_root_str = str(shim_root)
    if shim_root_str not in sys.path:
        sys.path.insert(0, shim_root_str)
    return shim_root


def test_find_repo_root_returns_current_git_root(tmp_path: Path) -> None:
    original_cwd = Path.cwd()
    (tmp_path / ".git").mkdir()
    os.chdir(tmp_path)
    try:
        assert MODULE.find_repo_root() == tmp_path
    finally:
        os.chdir(original_cwd)


def test_load_registry_valid_file(tmp_path: Path) -> None:
    registry_path = tmp_path / "lint-registry.json"
    payload = {"languages": {"python": {"linter": {"name": "ruff"}}}}
    write_json(registry_path, payload)

    loaded = MODULE.load_registry(registry_path)

    assert loaded == payload


def test_load_registry_missing_file_exits(tmp_path: Path) -> None:
    missing = tmp_path / "missing-registry.json"

    import pytest

    with pytest.raises(SystemExit) as exc_info:
        MODULE.load_registry(missing)

    assert exc_info.value.code == 1


def test_load_detection_result_valid_file(tmp_path: Path) -> None:
    detection_path = tmp_path / "detection.json"
    payload = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }
    write_json(detection_path, payload)

    loaded = MODULE.load_detection_result(str(detection_path))

    assert loaded == payload


def test_load_detection_result_missing_file_exits(tmp_path: Path) -> None:
    missing = tmp_path / "missing-detection.json"

    import pytest

    with pytest.raises(SystemExit) as exc_info:
        MODULE.load_detection_result(str(missing))

    assert exc_info.value.code == 1


def test_check_existing_configs_returns_existing_entries() -> None:
    detection = {
        "existing_linter_configs": [
            {"tool": "ruff", "path": "pyproject.toml", "section": "tool.ruff"}
        ]
    }

    result = MODULE.check_existing_configs(detection)

    assert result == detection["existing_linter_configs"]


def test_check_existing_configs_returns_empty_when_not_present() -> None:
    result = MODULE.check_existing_configs({"languages": []})

    assert result == []


def test_has_conflicting_tools_python_conflict() -> None:
    registry = load_real_registry()
    existing_configs = [{"tool": "flake8", "path": ".flake8", "section": "flake8"}]

    result = MODULE.has_conflicting_tools(existing_configs, "python", registry)

    assert result is True


def test_has_conflicting_tools_javascript_conflict() -> None:
    registry = load_real_registry()
    existing_configs = [{"tool": "biome", "path": "biome.json", "section": ""}]

    result = MODULE.has_conflicting_tools(existing_configs, "javascript", registry)

    assert result is True


def test_has_conflicting_tools_no_conflict() -> None:
    registry = load_real_registry()
    existing_configs = [{"tool": "mypy", "path": "mypy.ini", "section": "mypy"}]

    result = MODULE.has_conflicting_tools(existing_configs, "python", registry)

    assert result is False


def test_has_conflicting_tools_unknown_language() -> None:
    registry = load_real_registry()
    existing_configs = [{"tool": "flake8", "path": ".flake8", "section": "flake8"}]

    result = MODULE.has_conflicting_tools(existing_configs, "elixir", registry)

    assert result is False


def test_lookup_toolchain_existing_language() -> None:
    registry = load_real_registry()

    result = MODULE.lookup_toolchain("python", registry)

    assert isinstance(result, dict)
    assert result["linter"]["name"] == "ruff"


def test_lookup_toolchain_missing_language_returns_none() -> None:
    registry = load_real_registry()

    result = MODULE.lookup_toolchain("elixir", registry)

    assert result is None


def test_generate_python_ruff_config_generates_content(tmp_path: Path) -> None:
    toolchain = minimal_registry()["languages"]["python"]

    config = MODULE.generate_python_ruff_config(toolchain, tmp_path)

    assert isinstance(config, str)
    assert "[tool.ruff]" in config
    assert 'target-version = "py311"' in config
    assert '"E4"' in config
    assert '"F"' in config
    assert "ignore = [" in config
    assert '"ISC001"' in config


def test_generate_python_ruff_config_skips_when_existing_ruff(tmp_path: Path) -> None:
    toolchain = minimal_registry()["languages"]["python"]
    existing = [{"tool": "ruff", "path": "pyproject.toml", "section": "tool.ruff"}]

    config = MODULE.generate_python_ruff_config(
        toolchain, tmp_path, existing_configs=existing
    )

    assert config is None


def test_generate_python_ruff_config_dry_run_returns_none(tmp_path: Path) -> None:
    toolchain = minimal_registry()["languages"]["python"]

    config = MODULE.generate_python_ruff_config(toolchain, tmp_path, dry_run=True)

    assert config is None


def test_generate_ci_commands_single_language() -> None:
    registry = minimal_registry()

    commands = MODULE.generate_ci_commands(["python"], registry)

    assert commands == [
        {"key": "AGENTIC_SDD_CI_LINT_CMD", "value": "ruff check ."},
        {"key": "AGENTIC_SDD_CI_FORMAT_CMD", "value": "ruff format --check ."},
        {"key": "AGENTIC_SDD_CI_TYPECHECK_CMD", "value": "mypy ."},
    ]


def test_generate_ci_commands_multiple_languages_deduplicates_keys() -> None:
    registry = minimal_registry()

    commands = MODULE.generate_ci_commands(
        ["python", "javascript", "typescript"], registry
    )

    assert commands == [
        {"key": "AGENTIC_SDD_CI_LINT_CMD", "value": "ruff check ."},
        {"key": "AGENTIC_SDD_CI_FORMAT_CMD", "value": "ruff format --check ."},
        {"key": "AGENTIC_SDD_CI_TYPECHECK_CMD", "value": "mypy ."},
    ]


def test_generate_ci_commands_skips_unknown_language() -> None:
    registry = minimal_registry()

    commands = MODULE.generate_ci_commands(["unknown", "python"], registry)

    assert commands == [
        {"key": "AGENTIC_SDD_CI_LINT_CMD", "value": "ruff check ."},
        {"key": "AGENTIC_SDD_CI_FORMAT_CMD", "value": "ruff format --check ."},
        {"key": "AGENTIC_SDD_CI_TYPECHECK_CMD", "value": "mypy ."},
    ]


def test_generate_evidence_trail_generates_file(tmp_path: Path) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }
    generated_files = ["pyproject.toml [tool.ruff]"]
    ci_commands = [{"key": "AGENTIC_SDD_CI_LINT_CMD", "value": "ruff check ."}]

    output_path = MODULE.generate_evidence_trail(
        detection,
        registry,
        generated_files,
        ci_commands,
        tmp_path,
        template_dir=TEMPLATE_DIR,
    )

    assert isinstance(output_path, str)
    evidence_path = Path(output_path)
    assert evidence_path.exists()
    content = evidence_path.read_text(encoding="utf-8")
    assert "ruff" in content
    assert "python" in content


def test_generate_evidence_trail_dry_run_returns_rendered_content(
    tmp_path: Path,
) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }

    content = MODULE.generate_evidence_trail(
        detection,
        registry,
        generated_files=[],
        ci_commands=[],
        target_dir=tmp_path,
        template_dir=TEMPLATE_DIR,
        dry_run=True,
    )

    assert isinstance(content, str)
    assert "python" in content
    assert not (tmp_path / ".agentic-sdd" / "project" / "rules" / "lint.md").exists()


def test_generate_evidence_trail_missing_template_dir_returns_none(
    tmp_path: Path,
) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }

    content = MODULE.generate_evidence_trail(
        detection,
        registry,
        generated_files=[],
        ci_commands=[],
        target_dir=tmp_path,
        template_dir=tmp_path / "missing-template-dir",
    )

    assert content is None


def test_run_setup_normal_single_language_flow(tmp_path: Path) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }

    result = MODULE.run_setup(
        detection,
        registry,
        tmp_path,
        dry_run=False,
        template_dir=TEMPLATE_DIR,
    )

    assert result["mode"] == "generate"
    assert result["languages"] == ["python"]
    assert "pyproject.toml [tool.ruff]" in result["generated_files"]
    assert any(
        str(path).endswith(".agentic-sdd/project/rules/lint.md")
        for path in result["generated_files"]
    )
    assert result["ci_commands"]


def test_run_setup_monorepo_multilanguage_downgrades_to_proposal(
    tmp_path: Path,
) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [
            {"name": "python", "source": "pyproject.toml", "path": "backend"},
            {"name": "javascript", "source": "package.json", "path": "frontend"},
        ],
        "existing_linter_configs": [],
        "is_monorepo": True,
    }

    result = MODULE.run_setup(
        detection,
        registry,
        tmp_path,
        dry_run=False,
        template_dir=TEMPLATE_DIR,
    )

    assert result["mode"] == "proposal"
    assert "proposals" in result
    assert len(result["proposals"]) == 2
    assert "pyproject.toml [tool.ruff]" not in result["generated_files"]


def test_run_setup_empty_languages_returns_error(tmp_path: Path) -> None:
    registry = load_real_registry()
    detection = {
        "languages": [],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }

    result = MODULE.run_setup(detection, registry, tmp_path)

    assert result == {"error": "no_languages_detected", "generated_files": []}


def test_run_setup_conflicting_tools_downgrades_to_proposal(tmp_path: Path) -> None:
    ensure_jinja2_available(tmp_path)
    registry = load_real_registry()
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [
            {"tool": "flake8", "path": ".flake8", "section": "flake8"}
        ],
        "is_monorepo": False,
    }

    result = MODULE.run_setup(
        detection,
        registry,
        tmp_path,
        dry_run=False,
        template_dir=TEMPLATE_DIR,
    )

    assert result["mode"] == "proposal"
    assert "proposals" in result
    assert len(result["proposals"]) == 1
    assert "existing_configs" in result


def test_cli_integration_json_output(tmp_path: Path) -> None:
    shim_root = ensure_jinja2_available(tmp_path)
    detection_path = tmp_path / "detection.json"
    detection = {
        "languages": [{"name": "python", "source": "pyproject.toml", "path": "."}],
        "existing_linter_configs": [],
        "is_monorepo": False,
    }
    write_json(detection_path, detection)

    env = os.environ.copy()
    if shim_root is not None:
        pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = (
            str(shim_root) if not pythonpath else f"{str(shim_root)}:{pythonpath}"
        )

    proc = subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(detection_path),
            "--registry",
            str(REGISTRY_PATH),
            "--template-dir",
            str(TEMPLATE_DIR),
            "--target-dir",
            str(tmp_path),
            "--json",
        ],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )

    assert proc.returncode == 0
    output = json.loads(proc.stdout)
    assert output["mode"] == "generate"
    assert output["languages"] == ["python"]
    assert any(
        str(path).endswith(".agentic-sdd/project/rules/lint.md")
        for path in output["generated_files"]
    )
