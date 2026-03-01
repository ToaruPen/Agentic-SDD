from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def test_wrapper_help_delegates_to_target_and_emits_warning() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    wrapper = repo_root / "scripts" / "extract-epic-config.py"

    proc = subprocess.run(  # noqa: S603
        [sys.executable, str(wrapper), "--help"],
        check=False,
        capture_output=True,
        text=True,
    )

    assert proc.returncode == 0
    assert "Epic情報を抽出してJSON形式で出力" in proc.stdout


def test_wrapper_propagates_nonzero_exit_code_for_missing_file() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    wrapper = repo_root / "scripts" / "extract-epic-config.py"
    target = repo_root / "scripts" / "extract" / "extract_epic_config.py"
    missing = repo_root / "does-not-exist-epic.md"

    target_proc = subprocess.run(  # noqa: S603
        [sys.executable, str(target), str(missing)],
        check=False,
        capture_output=True,
        text=True,
    )
    wrapper_proc = subprocess.run(  # noqa: S603
        [sys.executable, str(wrapper), str(missing)],
        check=False,
        capture_output=True,
        text=True,
    )

    assert wrapper_proc.returncode == target_proc.returncode


def test_wrapper_preserves_arguments_for_argparse_errors() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    wrapper = repo_root / "scripts" / "extract-epic-config.py"
    target = repo_root / "scripts" / "extract" / "extract_epic_config.py"

    target_proc = subprocess.run(  # noqa: S603
        [sys.executable, str(target), "--this-option-does-not-exist"],
        check=False,
        capture_output=True,
        text=True,
    )
    wrapper_proc = subprocess.run(  # noqa: S603
        [sys.executable, str(wrapper), "--this-option-does-not-exist"],
        check=False,
        capture_output=True,
        text=True,
    )

    assert target_proc.returncode == 2
    assert wrapper_proc.returncode == target_proc.returncode
    assert target_proc.stderr.strip() in wrapper_proc.stderr
