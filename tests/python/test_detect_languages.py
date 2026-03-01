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


def test_detect_kotlin_language(tmp_path: Path) -> None:
    write_file(tmp_path / "Main.kt", "fun main() {}\n")

    result = MODULE.detect_project(tmp_path)

    assert "kotlin" in language_names(result)


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


def test_detect_not_monorepo(tmp_path: Path) -> None:
    write_file(tmp_path / "build.gradle", "apply plugin: 'java'\n")
    write_file(
        tmp_path / "src" / "main" / "java" / "Main.java", "public class Main {}\n"
    )

    result = MODULE.detect_project(tmp_path)

    assert result["is_monorepo"] is False
    assert result["subprojects"] == []

def test_detect_monorepo_with_root_config(tmp_path: Path) -> None:
    """Root-level config plus multiple subprojects should still be detected as monorepo."""
    write_file(tmp_path / "package.json", "{}")
    write_file(tmp_path / "backend" / "go.mod", "module example.com/backend\n")
    write_file(tmp_path / "frontend" / "package.json", "{}")

    result = MODULE.detect_project(tmp_path)

    assert result["is_monorepo"] is True
    subprojects = result["subprojects"]
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


def test_cli_non_existent_path(tmp_path: Path) -> None:
    script_path = (
        Path(__file__).resolve().parents[2] / "scripts" / "detect-languages.py"
    )
    proc = subprocess.run(
        [
            sys.executable,
            str(script_path),
            "--path",
            str(tmp_path / "missing"),
            "--json",
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 1
    assert "Error: Path not found" in proc.stderr


def test_settings_gradle_kts_does_not_confirm_kotlin(tmp_path: Path) -> None:
    """settings.gradle.kts is Gradle DSL, not Kotlin source code.

    Only build.gradle.kts should produce an inferred detection.
    settings.gradle.kts should NOT produce any Kotlin detection at all.
    """
    write_file(tmp_path / "settings.gradle.kts", "rootProject.name = 'demo'\n")

    result = MODULE.detect_project(tmp_path)

    kotlin_detections = [
        lang for lang in result["languages"] if lang["name"] == "kotlin"
    ]
    assert kotlin_detections == [], (
        f"settings.gradle.kts should not detect Kotlin but got: {kotlin_detections}"
    )


def test_build_gradle_kts_infers_kotlin_and_java(tmp_path: Path) -> None:
    """build.gradle.kts should infer both Kotlin and Java, not confirm either."""
    write_file(tmp_path / "build.gradle.kts", 'plugins { kotlin("jvm") }\n')

    result = MODULE.detect_project(tmp_path)

    kotlin_detections = [
        lang for lang in result["languages"] if lang["name"] == "kotlin"
    ]
    assert len(kotlin_detections) == 1
    assert kotlin_detections[0]["confidence"] == "inferred"

    java_detections = [lang for lang in result["languages"] if lang["name"] == "java"]
    assert len(java_detections) == 1
    assert java_detections[0]["confidence"] == "inferred"


def test_kt_file_confirms_kotlin(tmp_path: Path) -> None:
    """Actual .kt source files should produce confirmed Kotlin detection."""
    write_file(tmp_path / "Main.kt", "fun main() {}\n")

    result = MODULE.detect_project(tmp_path)

    kotlin_detections = [
        lang for lang in result["languages"] if lang["name"] == "kotlin"
    ]
    assert len(kotlin_detections) == 1
    assert "confidence" not in kotlin_detections[0]  # confirmed = no confidence key


def test_malformed_setup_cfg_does_not_crash(tmp_path: Path) -> None:
    """Malformed setup.cfg should be skipped gracefully, not crash detection."""
    write_file(tmp_path / "pyproject.toml", "[project]\nname = 'demo'\n")
    # Write invalid content that will fail configparser parsing
    write_file(tmp_path / "setup.cfg", "\x00\x01\x02not valid ini\n")

    result = MODULE.detect_project(tmp_path)

    # Should still detect python from pyproject.toml
    assert "python" in language_names(result)
    # Should not have flake8 in linter configs (setup.cfg was malformed)
    linter_tools = {
        entry["tool"]
        for entry in result.get("existing_linter_configs", [])
        if isinstance(entry, dict)
    }
    assert "flake8" not in linter_tools


def test_build_gradle_infers_java(tmp_path: Path) -> None:
    """build.gradle should infer Java (not confirm), since Gradle is used for non-Java too."""
    write_file(tmp_path / "build.gradle", "apply plugin: 'java'\n")

    result = MODULE.detect_project(tmp_path)

    java_detections = [lang for lang in result["languages"] if lang["name"] == "java"]
    assert len(java_detections) == 1
    assert java_detections[0]["confidence"] == "inferred"


def test_java_source_confirms_java(tmp_path: Path) -> None:
    """Actual .java source files should produce confirmed Java detection."""
    write_file(tmp_path / "Main.java", "public class Main {}\n")

    result = MODULE.detect_project(tmp_path)

    java_detections = [lang for lang in result["languages"] if lang["name"] == "java"]
    assert len(java_detections) == 1
    assert "confidence" not in java_detections[0]  # confirmed = no confidence key
