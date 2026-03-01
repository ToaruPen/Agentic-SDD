#!/usr/bin/env python3

from __future__ import annotations

import argparse
import configparser
import json
import os
import sys
import tomllib
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def to_rel_dir(path: Path, root: Path) -> str:
    rel = path.relative_to(root)
    if str(rel) == ".":
        return "."
    return rel.as_posix()


def iter_files(root: Path) -> Iterator[Path]:
    """Walk the file tree, skipping dependency/vendor/hidden directories."""
    skip_dirs = {
        ".venv",
        "venv",
        "node_modules",
        ".git",
        "__pycache__",
        ".tox",
        ".mypy_cache",
        ".pytest_cache",
        ".ruff_cache",
        "vendor",
        "dist",
        "build",
        ".next",
        "target",
    }

    def onerror(err: OSError) -> None:
        filename = err.filename or "<unknown>"
        raise RuntimeError(
            f"Failed to read directory: {filename}: {err.strerror}"
        ) from err

    for dirpath, dirnames, filenames in os.walk(root, onerror=onerror):
        dirnames[:] = [
            d for d in dirnames if d not in skip_dirs and not d.startswith(".")
        ]
        base = Path(dirpath)
        for filename in filenames:
            yield base / filename


def load_toml(path: Path) -> Dict[str, Any]:
    try:
        with path.open("rb") as fh:
            data = tomllib.load(fh)
    except OSError as exc:
        raise RuntimeError(f"Failed to read file: {path}: {exc}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise RuntimeError(f"Failed to parse TOML: {path}: {exc}") from exc
    if not isinstance(data, dict):
        return {}
    return data


def load_setup_cfg(path: Path) -> configparser.ConfigParser:
    parser = configparser.ConfigParser()
    try:
        with path.open("r", encoding="utf-8") as fh:
            parser.read_file(fh)
    except OSError as exc:
        raise RuntimeError(f"Failed to read file: {path}: {exc}") from exc
    except configparser.Error as exc:
        raise RuntimeError(f"Failed to parse setup.cfg: {path}: {exc}") from exc
    return parser


def has_toml_section(data: Dict[str, Any], dotted_path: Sequence[str]) -> bool:
    current: Any = data
    for key in dotted_path:
        if not isinstance(current, dict) or key not in current:
            return False
        current = current[key]
    return True


def detect_languages_for_file(file_path: Path, root: Path) -> List[Dict[str, str]]:
    rel_dir = to_rel_dir(file_path.parent, root)
    name = file_path.name
    detections: List[Dict[str, str]] = []

    if name in {"pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"}:
        detections.append({"name": "python", "source": name, "path": rel_dir})

    if name == "package.json":
        detections.append({"name": "javascript", "source": name, "path": rel_dir})

    if name == "tsconfig.json":
        detections.append({"name": "typescript", "source": name, "path": rel_dir})

    if name == "go.mod":
        detections.append({"name": "go", "source": name, "path": rel_dir})

    if name == "Cargo.toml":
        detections.append({"name": "rust", "source": name, "path": rel_dir})

    if name == "Gemfile" or file_path.suffix == ".gemspec":
        detections.append({"name": "ruby", "source": name, "path": rel_dir})

    if name in {"pom.xml", "build.gradle", "build.gradle.kts"}:
        detections.append({"name": "java", "source": name, "path": rel_dir})

    if file_path.suffix == ".kt" or file_path.suffix == ".kts":
        if name != "build.gradle.kts":  # Gradle Kotlin DSL は Java として検出済み
            detections.append({"name": "kotlin", "source": name, "path": rel_dir})

    return detections


def maybe_add_section(
    output: List[Dict[str, str]],
    tool: str,
    rel_path: str,
    section: Optional[str] = None,
) -> None:
    item: Dict[str, str] = {"tool": tool, "path": rel_path}
    if section is not None:
        item["section"] = section
    output.append(item)


def detect_linter_configs_for_file(file_path: Path, root: Path) -> List[Dict[str, str]]:
    rel_path = file_path.relative_to(root).as_posix()
    name = file_path.name
    detections: List[Dict[str, str]] = []

    if name.startswith(".eslintrc") or name.startswith("eslint.config."):
        maybe_add_section(detections, "eslint", rel_path)

    if name == "ruff.toml":
        maybe_add_section(detections, "ruff", rel_path)

    if name in {".golangci.yml", ".golangci.yaml"}:
        maybe_add_section(detections, "golangci-lint", rel_path)

    if name in {"clippy.toml", ".clippy.toml"}:
        maybe_add_section(detections, "clippy", rel_path)

    if name in {"biome.json", "biome.jsonc"}:
        maybe_add_section(detections, "biome", rel_path)

    if name.startswith(".prettierrc") or name.startswith("prettier.config."):
        maybe_add_section(detections, "prettier", rel_path)

    if name == ".flake8":
        maybe_add_section(detections, "flake8", rel_path)

    if name == ".rubocop.yml":
        maybe_add_section(detections, "rubocop", rel_path)

    if name in {"mypy.ini", ".mypy.ini"}:
        maybe_add_section(detections, "mypy", rel_path)

    if name == "pyproject.toml":
        data = load_toml(file_path)
        if has_toml_section(data, ("tool", "ruff")):
            maybe_add_section(detections, "ruff", rel_path, "tool.ruff")
        if has_toml_section(data, ("tool", "mypy")):
            maybe_add_section(detections, "mypy", rel_path, "tool.mypy")

    if name == "setup.cfg":
        parser = load_setup_cfg(file_path)
        if parser.has_section("flake8"):
            maybe_add_section(detections, "flake8", rel_path, "flake8")

    return detections


def dedupe_entries(
    entries: Iterable[Dict[str, str]], keys: Tuple[str, ...]
) -> List[Dict[str, str]]:
    seen: Set[Tuple[str, ...]] = set()
    result: List[Dict[str, str]] = []
    for entry in entries:
        marker = tuple(entry.get(key, "") for key in keys)
        if marker in seen:
            continue
        seen.add(marker)
        result.append(entry)
    return result


def detect_project(root: Path) -> Dict[str, Any]:
    if not root.exists():
        raise RuntimeError(f"Path not found: {root}")
    if not root.is_dir():
        raise RuntimeError(f"Path is not a directory: {root}")

    languages: List[Dict[str, str]] = []
    linters: List[Dict[str, str]] = []

    for file_path in iter_files(root):
        languages.extend(detect_languages_for_file(file_path, root))
        linters.extend(detect_linter_configs_for_file(file_path, root))

    languages = dedupe_entries(languages, ("name", "source", "path"))
    languages.sort(key=lambda item: (item["path"], item["name"], item["source"]))

    linters = dedupe_entries(linters, ("tool", "path", "section"))
    linters.sort(key=lambda item: (item["path"], item["tool"], item.get("section", "")))

    is_monorepo = False
    for i, left in enumerate(languages):
        for right in languages[i + 1 :]:
            if left["path"] != right["path"]:
                is_monorepo = True
                break
        if is_monorepo:
            break

    subprojects: List[Dict[str, Any]] = []
    if is_monorepo:
        path_to_languages: Dict[str, Set[str]] = {}
        for entry in languages:
            path_to_languages.setdefault(entry["path"], set()).add(entry["name"])
        for path_key in sorted(path_to_languages):
            if path_key == ".":
                continue
            subprojects.append(
                {
                    "path": path_key,
                    "languages": sorted(path_to_languages[path_key]),
                }
            )

    return {
        "languages": languages,
        "existing_linter_configs": linters,
        "is_monorepo": is_monorepo,
        "subprojects": subprojects,
    }


def print_text_report(result: Dict[str, Any]) -> None:
    print("Detected languages:")
    for item in result["languages"]:
        print(f"- {item['name']} (source={item['source']}, path={item['path']})")

    print("Existing linter configs:")
    for item in result["existing_linter_configs"]:
        section = item.get("section")
        if section:
            print(f"- {item['tool']} (path={item['path']}, section={section})")
        else:
            print(f"- {item['tool']} (path={item['path']})")

    print(f"is_monorepo: {result['is_monorepo']}")
    print("subprojects:")
    for item in result["subprojects"]:
        langs = ",".join(item["languages"])
        print(f"- {item['path']}: {langs}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect project languages and existing linter configurations."
    )
    parser.add_argument(
        "--path",
        default=".",
        help="Directory to scan (default: current directory).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON.",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    root = Path(args.path).resolve()
    try:
        result = detect_project(root)
    except RuntimeError as exc:
        eprint(f"Error: {exc}")
        return 1

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print_text_report(result)

    return 0


if __name__ == "__main__":
    sys.exit(main())
