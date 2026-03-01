from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest


def load_module() -> ModuleType:
    repo_root = Path(__file__).resolve().parents[2]
    scripts_dir = repo_root / "scripts"
    # Ensure _lib and cli_utils are importable
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    module_path = scripts_dir / "generate" / "generate_project_config.py"
    spec = importlib.util.spec_from_file_location(
        "generate_project_config", module_path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_module()


def test_find_repo_root_returns_path() -> None:
    """find_repo_root should return a Path that contains a .git directory."""
    result = MODULE.find_repo_root()
    assert isinstance(result, Path)
    # We're running inside a git repo, so .git should exist
    assert (result / ".git").exists()


class _DummyTemplate:
    def __init__(self, name: str) -> None:
        self.name = name

    def render(self, **context: Any) -> str:
        if self.name == "config.json.j2":
            return json.dumps(
                {
                    "generated_skills": context.get("generated_skills", []),
                    "generated_rules": context.get("generated_rules", []),
                },
                ensure_ascii=False,
            )
        return f"# {self.name}\n"


class _DummyEnv:
    def get_template(self, name: str) -> _DummyTemplate:
        return _DummyTemplate(name)


def _sample_config() -> dict[str, Any]:
    return {
        "epic_path": "docs/epics/epic.md",
        "meta": {"prd_path": "docs/prd/prd.md"},
        "tech_stack": {"language": "python"},
        "requirements": {
            "security": True,
            "performance": True,
            "details": {"security": {}, "performance": {}},
        },
        "api_design": [{"method": "GET", "path": "/health"}],
    }


def test_load_config_valid_json(tmp_path: Path) -> None:
    """load_config should parse a valid JSON file into a dict."""
    path = tmp_path / "config.json"
    data = {"project_name": "test", "languages": ["python"]}
    path.write_text(json.dumps(data), encoding="utf-8")
    result = MODULE.load_config(str(path))
    assert result == data


def test_load_config_invalid_json_raises(tmp_path: Path) -> None:
    """load_config should raise JSONDecodeError for invalid JSON."""
    path = tmp_path / "config.json"
    path.write_text("not valid json {{{", encoding="utf-8")
    with pytest.raises(json.JSONDecodeError):
        MODULE.load_config(str(path))


def test_load_config_nonexistent_file_raises(tmp_path: Path) -> None:
    """load_config should raise FileNotFoundError for missing files."""
    missing = tmp_path / "nonexistent_config_file_abc123.json"
    with pytest.raises(FileNotFoundError):
        MODULE.load_config(str(missing))


def test_generate_all_happy_path_creates_expected_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(MODULE, "setup_jinja_env", lambda _template_dir: _DummyEnv())

    output_dir = tmp_path / "out"
    result = MODULE.generate_all(
        _sample_config(),
        tmp_path / "templates",
        output_dir,
        dry_run=False,
    )

    expected_files = {
        output_dir / "config.json",
        output_dir / "skills" / "tech-stack.md",
        output_dir / "rules" / "security.md",
        output_dir / "rules" / "performance.md",
        output_dir / "rules" / "api-conventions.md",
    }
    assert expected_files.issubset({Path(path) for path in result["generated_files"]})
    assert all(path.exists() for path in expected_files)


def test_main_happy_path_writes_generated_files(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(MODULE, "setup_jinja_env", lambda _template_dir: _DummyEnv())

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(_sample_config()), encoding="utf-8")
    output_dir = tmp_path / "generated"
    template_dir = tmp_path / "templates"
    template_dir.mkdir(parents=True)

    monkeypatch.setattr(
        MODULE.sys,
        "argv",
        [
            "generate_project_config.py",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--template-dir",
            str(template_dir),
            "--skip-lint",
        ],
    )

    assert MODULE.main() == 0
    assert (output_dir / "config.json").exists()
    assert (output_dir / "skills" / "tech-stack.md").exists()
    assert "生成完了" in capsys.readouterr().out


def test_main_dry_run_does_not_write_files(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(MODULE, "setup_jinja_env", lambda _template_dir: _DummyEnv())

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(_sample_config()), encoding="utf-8")
    output_dir = tmp_path / "generated"
    template_dir = tmp_path / "templates"
    template_dir.mkdir(parents=True)

    monkeypatch.setattr(
        MODULE.sys,
        "argv",
        [
            "generate_project_config.py",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--template-dir",
            str(template_dir),
            "--dry-run",
            "--skip-lint",
        ],
    )

    assert MODULE.main() == 0
    assert not output_dir.exists()
    assert "Dry Run" in capsys.readouterr().out


def test_main_json_flag_outputs_json(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(MODULE, "setup_jinja_env", lambda _template_dir: _DummyEnv())

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(_sample_config()), encoding="utf-8")
    output_dir = tmp_path / "generated"
    template_dir = tmp_path / "templates"
    template_dir.mkdir(parents=True)

    monkeypatch.setattr(
        MODULE.sys,
        "argv",
        [
            "generate_project_config.py",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--template-dir",
            str(template_dir),
            "--dry-run",
            "--skip-lint",
            "--json",
        ],
    )

    assert MODULE.main() == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["output_dir"] == str(output_dir)
    assert payload["generated_files"] == []
    assert payload["generated_skills"] == ["tech-stack.md"]


def test_main_lint_integration_invalid_json_warns_and_sets_error(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(MODULE, "setup_jinja_env", lambda _template_dir: _DummyEnv())
    monkeypatch.setattr(MODULE, "find_repo_root", lambda: tmp_path)

    def fake_run_cmd(
        cmd: list[str],
        cwd: str | None = None,
        check: bool = True,
        timeout: int | None = None,
        text: bool = True,
        capture_output: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        _ = (cwd, check, timeout, text, capture_output)
        target = Path(cmd[1]).name if len(cmd) > 1 else ""
        if target == "detect-languages.py":
            return subprocess.CompletedProcess(
                cmd, 0, stdout='{"languages": []}', stderr=""
            )
        if target == "lint-setup.py":
            return subprocess.CompletedProcess(
                cmd, 0, stdout="{invalid-json", stderr=""
            )
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    monkeypatch.setattr(MODULE, "run_cmd", fake_run_cmd)

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(_sample_config()), encoding="utf-8")
    output_dir = tmp_path / "generated"
    template_dir = tmp_path / "templates"
    template_dir.mkdir(parents=True)

    monkeypatch.setattr(
        MODULE.sys,
        "argv",
        [
            "generate_project_config.py",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--template-dir",
            str(template_dir),
            "--json",
        ],
    )

    assert MODULE.main() == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload["lint_setup"] == {}
    assert "lint_setup_error" in payload
    assert "invalid JSON output" in payload["lint_setup_error"]
    assert "lint-setup failed" in captured.err


def test_main_returns_nonzero_when_generate_all_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        MODULE,
        "generate_all",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("boom")),
    )

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(_sample_config()), encoding="utf-8")

    monkeypatch.setattr(
        MODULE.sys,
        "argv",
        [
            "generate_project_config.py",
            str(config_path),
            "--skip-lint",
        ],
    )

    assert MODULE.main() == 1
    assert "Failed to generate files" in capsys.readouterr().err
