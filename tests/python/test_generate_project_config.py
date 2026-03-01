from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path
from types import ModuleType

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


def test_load_config_valid_json() -> None:
    """load_config should parse a valid JSON file into a dict."""
    data = {"project_name": "test", "languages": ["python"]}
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(data, f)
        f.flush()
        result = MODULE.load_config(f.name)
    assert result == data
    Path(f.name).unlink()


def test_load_config_invalid_json_raises() -> None:
    """load_config should raise JSONDecodeError for invalid JSON."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        f.write("not valid json {{{")
        f.flush()
        with pytest.raises(json.JSONDecodeError):
            MODULE.load_config(f.name)
    Path(f.name).unlink()


def test_load_config_nonexistent_file_raises() -> None:
    """load_config should raise FileNotFoundError for missing files."""
    with pytest.raises(FileNotFoundError):
        MODULE.load_config("/tmp/nonexistent_config_file_abc123.json")  # noqa: S108
