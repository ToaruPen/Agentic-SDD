from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    module_path = repo_root / "scripts" / "detect-languages.py"
    spec = importlib.util.spec_from_file_location("detect_languages", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def language_names(result: dict[str, object]) -> set[str]:
    languages = result["languages"]
    assert isinstance(languages, list)
    return {item["name"] for item in languages if isinstance(item, dict)}


def test_detect_python_language(tmp_path: Path) -> None:
    write_file(tmp_path / "pyproject.toml", "[project]\nname = 'demo'\n")

    result = MODULE.detect_project(tmp_path)
    assert "python" in language_names(result)


def test_detect_typescript_and_javascript_language(tmp_path: Path) -> None:
    write_file(tmp_path / "package.json", "{}")
    write_file(tmp_path / "tsconfig.json", "{}")

    result = MODULE.detect_project(tmp_path)

    assert "javascript" in language_names(result)
    assert "typescript" in language_names(result)


def test_detect_go_language(tmp_path: Path) -> None:
    write_file(tmp_path / "go.mod", "module example.com/project\n")

    result = MODULE.detect_project(tmp_path)

    assert "go" in language_names(result)


def test_detect_rust_language(tmp_path: Path) -> None:
    write_file(tmp_path / "Cargo.toml", "[package]\nname='demo'\nversion='0.1.0'\n")

    result = MODULE.detect_project(tmp_path)

    assert "rust" in language_names(result)


def test_detect_ruby_language(tmp_path: Path) -> None:
    write_file(tmp_path / "app.gemspec", "Gem::Specification.new do |s|\nend\n")

    result = MODULE.detect_project(tmp_path)

    assert "ruby" in language_names(result)


def test_detect_java_language(tmp_path: Path) -> None:
    write_file(tmp_path / "pom.xml", "<project></project>\n")

    result = MODULE.detect_project(tmp_path)

    assert "java" in language_names(result)


def test_detect_existing_linter_configs(tmp_path: Path) -> None:
    write_file(
        tmp_path / "pyproject.toml",
        "[tool.ruff]\nline-length = 100\n[tool.mypy]\npython_version = '3.11'\n",
    )
    write_file(tmp_path / "eslint.config.js", "export default []\n")
    write_file(tmp_path / ".flake8", "[flake8]\nmax-line-length = 120\n")
    write_file(tmp_path / "setup.cfg", "[flake8]\nmax-line-length = 120\n")
    write_file(tmp_path / "mypy.ini", "[mypy]\nstrict = True\n")
    write_file(tmp_path / ".golangci.yml", "run:\n  timeout: 5m\n")
    write_file(tmp_path / "clippy.toml", "msrv = '1.70'\n")
    write_file(tmp_path / "biome.json", "{}")
    write_file(tmp_path / ".prettierrc.json", "{}")
    write_file(tmp_path / ".rubocop.yml", "AllCops:\n  NewCops: enable\n")

    result = MODULE.detect_project(tmp_path)

    linters = result["existing_linter_configs"]
    assert isinstance(linters, list)

    tools = {entry["tool"] for entry in linters if isinstance(entry, dict)}
    assert {
        "ruff",
        "mypy",
        "eslint",
        "flake8",
        "golangci-lint",
        "clippy",
        "biome",
        "prettier",
        "rubocop",
    }.issubset(tools)

    assert {"tool": "ruff", "path": "pyproject.toml", "section": "tool.ruff"} in linters
    assert {"tool": "mypy", "path": "pyproject.toml", "section": "tool.mypy"} in linters
    assert {"tool": "flake8", "path": "setup.cfg", "section": "flake8"} in linters


def test_detect_monorepo(tmp_path: Path) -> None:
    write_file(tmp_path / "backend" / "go.mod", "module example.com/backend\n")
    write_file(tmp_path / "frontend" / "package.json", "{}")

    result = MODULE.detect_project(tmp_path)

    assert result["is_monorepo"] is True
    subprojects = result["subprojects"]
    assert isinstance(subprojects, list)
    assert {"path": "backend", "languages": ["go"]} in subprojects
    assert {"path": "frontend", "languages": ["javascript"]} in subprojects


def test_cli_path_option(tmp_path: Path) -> None:
    write_file(
        tmp_path / "services" / "api" / "pyproject.toml",
        "[tool.ruff]\nline-length = 100\n",
    )

    script_path = (
        Path(__file__).resolve().parents[2] / "scripts" / "detect-languages.py"
    )
    proc = subprocess.run(
        [
            sys.executable,
            str(script_path),
            "--path",
            str(tmp_path / "services" / "api"),
            "--json",
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 0
    output = json.loads(proc.stdout)
    assert {"name": "python", "source": "pyproject.toml", "path": "."} in output[
        "languages"
    ]


def test_cli_non_existent_path() -> None:
    script_path = (
        Path(__file__).resolve().parents[2] / "scripts" / "detect-languages.py"
    )
    proc = subprocess.run(
        [sys.executable, str(script_path), "--path", "__missing_dir__", "--json"],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 1
    assert "Error: Path not found" in proc.stderr
