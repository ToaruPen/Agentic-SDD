#!/usr/bin/env python3
"""
Linter設定生成スクリプト

detect-languages.py の出力と lint-registry.json を組み合わせて、
推奨 linter 設定ファイルと証跡ドキュメントを生成する。
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def find_repo_root() -> Path:
    """リポジトリのルートディレクトリを検出"""
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return Path.cwd()


def load_registry(registry_path: Path) -> Dict[str, Any]:
    """lint-registry.json を読み込む"""
    if not registry_path.exists():
        eprint(f"Error: Registry file not found: {registry_path}")
        sys.exit(1)
    with open(registry_path, encoding="utf-8") as fh:
        return json.load(fh)


def load_detection_result(detection_path: str) -> Dict[str, Any]:
    """detect-languages.py の JSON 出力を読み込む"""
    path = Path(detection_path)
    if not path.exists():
        eprint(f"Error: Detection result file not found: {path}")
        sys.exit(1)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def check_existing_configs(
    detection: Dict[str, Any],
) -> List[Dict[str, str]]:
    """既存 linter 設定の競合を検出"""
    return detection.get("existing_linter_configs", [])


def has_conflicting_tools(
    existing_configs: List[Dict[str, str]],
    language: str,
    registry: Dict[str, Any],
) -> bool:
    """同一言語に対して複数の競合する linter があるか判定"""
    lang_config = registry.get("languages", {}).get(language)
    if not lang_config:
        return False

    recommended_linter = lang_config.get("linter", {}).get("name", "")
    existing_linters = [
        c["tool"] for c in existing_configs if c.get("tool", "") != recommended_linter
    ]

    # 同一目的の異なるツールが存在する場合
    linter_names = {recommended_linter} | set(existing_linters)
    # Python: ruff vs flake8 vs pylint
    python_linters = {"ruff", "flake8", "pylint"}
    if language == "python" and len(linter_names & python_linters) > 1:
        return True
    # JS/TS: eslint vs biome
    js_linters = {"eslint", "biome"}
    if language in ("typescript", "javascript") and len(linter_names & js_linters) > 1:
        return True
    return False


def lookup_toolchain(
    language: str,
    registry: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """レジストリから言語のツールチェーンを取得"""
    languages = registry.get("languages", {})
    return languages.get(language)


def generate_python_ruff_config(
    toolchain: Dict[str, Any],
    target_dir: Path,
    dry_run: bool = False,
    existing_configs: Optional[List[Dict[str, str]]] = None,
) -> Optional[str]:
    """Python 用の ruff 設定を pyproject.toml に生成"""
    existing = existing_configs or []

    # 既に ruff 設定がある場合はスキップ
    for config in existing:
        if config.get("tool") == "ruff":
            eprint(f"[SKIP] 既存の ruff 設定を検出: {config.get('path')}（上書き不可）")
            return None

    linter = toolchain.get("linter", {})
    formatter = toolchain.get("formatter", {})

    essential = linter.get("essential_rules", [])
    conflict_rules = formatter.get("conflict_rules", [])

    # pyproject.toml の [tool.ruff] セクションを生成
    lines = [
        "[tool.ruff]",
        'target-version = "py311"',
        "",
        "[tool.ruff.lint]",
        "select = [",
    ]
    for rule in essential:
        lines.append(f'  "{rule}",')
    lines.append("]")
    lines.append("")

    if conflict_rules:
        lines.append("ignore = [")
        for rule in conflict_rules:
            lines.append(f'  "{rule}",')
        lines.append("]")

    config_content = "\n".join(lines) + "\n"

    if dry_run:
        eprint(f"[DRY-RUN] Would generate ruff config in {target_dir}/pyproject.toml")
        eprint(config_content)
        return None

    return config_content


def generate_ci_commands(
    languages: List[str],
    registry: Dict[str, Any],
) -> List[Dict[str, str]]:
    """CI 推奨コマンドを生成"""
    commands: List[Dict[str, str]] = []
    seen_keys: set[str] = set()

    for lang in languages:
        toolchain = lookup_toolchain(lang, registry)
        if not toolchain:
            continue

        linter = toolchain.get("linter", {})
        formatter = toolchain.get("formatter", {})
        type_checker = toolchain.get("type_checker", {})

        lint_cmd = linter.get("ci_command")
        if lint_cmd and "LINT" not in seen_keys:
            commands.append({"key": "AGENTIC_SDD_CI_LINT_CMD", "value": lint_cmd})
            seen_keys.add("LINT")

        fmt_cmd = formatter.get("ci_command")
        if fmt_cmd and "FORMAT" not in seen_keys:
            commands.append({"key": "AGENTIC_SDD_CI_FORMAT_CMD", "value": fmt_cmd})
            seen_keys.add("FORMAT")

        tc_cmd = type_checker.get("ci_command")
        if tc_cmd and "TYPECHECK" not in seen_keys:
            commands.append({"key": "AGENTIC_SDD_CI_TYPECHECK_CMD", "value": tc_cmd})
            seen_keys.add("TYPECHECK")

    return commands


def generate_evidence_trail(
    detection: Dict[str, Any],
    registry: Dict[str, Any],
    generated_files: List[str],
    ci_commands: List[Dict[str, str]],
    target_dir: Path,
    template_dir: Optional[Path] = None,
    dry_run: bool = False,
) -> Optional[str]:
    """証跡ファイル (.agentic-sdd/project/rules/lint.md) を生成"""
    try:
        from jinja2 import Environment, FileSystemLoader
    except ImportError:
        eprint("[WARN] jinja2 not available; skipping evidence trail generation")
        return None

    if template_dir is None:
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent
        template_dir = repo_root / "templates" / "project-config"

    if not template_dir.exists():
        eprint(f"[WARN] Template directory not found: {template_dir}")
        return None

    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        trim_blocks=True,
        lstrip_blocks=True,
        autoescape=True,
    )

    languages = detection.get("languages", [])
    existing_configs = detection.get("existing_linter_configs", [])

    toolchains = []
    for lang_info in languages:
        lang_name = lang_info["name"]
        toolchain = lookup_toolchain(lang_name, registry)
        if not toolchain:
            continue

        linter = toolchain.get("linter", {})
        formatter = toolchain.get("formatter", {})
        type_checker = toolchain.get("type_checker", {})

        toolchains.append(
            {
                "language": lang_name,
                "linter_name": linter.get("name", "N/A"),
                "linter_docs_url": linter.get("docs_url", "N/A"),
                "formatter_name": formatter.get("name", "N/A"),
                "formatter_docs_url": formatter.get("docs_url", "N/A"),
                "type_checker_name": type_checker.get("name"),
                "type_checker_docs_url": type_checker.get("docs_url"),
                "references": [
                    {
                        "url": linter.get("docs_url", ""),
                        "registered_at": datetime.now(tz=timezone.utc).isoformat(),
                        "note": "URL from registry; agent fetches actual docs at runtime via webfetch/librarian",
                    }
                ],
                "essential_rules": linter.get("essential_rules", []),
                "recommended_rules": linter.get("recommended_rules", []),
                "framework_rules": [],
                "conflict_exclusions": formatter.get("conflict_rules", []),
            }
        )

    context = {
        "generated_at": datetime.now(tz=timezone.utc).isoformat(),
        "target_path": str(target_dir),
        "languages": languages,
        "toolchains": toolchains,
        "existing_configs": existing_configs,
        "generated_files": generated_files,
        "ci_commands": ci_commands,
    }

    template = env.get_template("rules/lint.md.j2")
    content = template.render(**context)

    output_dir = target_dir / ".agentic-sdd" / "project" / "rules"

    if dry_run:
        eprint(f"[DRY-RUN] Would generate evidence trail: {output_dir / 'lint.md'}")
        return content

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "lint.md"
    output_path.write_text(content, encoding="utf-8")
    return str(output_path)


def run_setup(
    detection: Dict[str, Any],
    registry: Dict[str, Any],
    target_dir: Path,
    dry_run: bool = False,
    template_dir: Optional[Path] = None,
) -> Dict[str, Any]:
    """メインのセットアップ処理"""
    languages = detection.get("languages", [])
    existing_configs = detection.get("existing_linter_configs", [])
    is_monorepo = detection.get("is_monorepo", False)

    if not languages:
        eprint("[ERROR] 言語を検出できませんでした。")
        return {"error": "no_languages_detected", "generated_files": []}

    lang_names = [lang["name"] for lang in languages]
    generated_files: List[str] = []
    proposals: List[str] = []
    mode = "generate"
    processed_languages: set[str] = set()

    # monorepo で複数言語の場合は提案モードに格下げ
    if is_monorepo and len(set(lang_names)) > 1:
        mode = "proposal"
        eprint(
            "[WARN] Monorepo で複数言語を検出しました。自動生成を中断し、提案のみ出力します。"
        )

    for lang_info in languages:
        lang_name = lang_info["name"]
        if lang_name in processed_languages:
            continue
        processed_languages.add(lang_name)
        toolchain = lookup_toolchain(lang_name, registry)
        if not toolchain:
            eprint(
                f"[WARN] レジストリに未登録の言語を検出: {lang_name}。手動での linter 設定が必要です。"
            )
            continue

        # 競合チェック
        if has_conflicting_tools(existing_configs, lang_name, registry):
            eprint(
                f"[WARN] {lang_name}: 複数の競合する linter 設定を検出しました。提案のみ出力します。"
            )
            mode = "proposal"

        if mode == "proposal":
            linter = toolchain.get("linter", {})
            proposals.append(
                f"  - {lang_name}: {linter.get('name')} を推奨 (docs: {linter.get('docs_url')})"
            )
            continue

        # Python の場合は ruff 設定を生成
        if lang_name == "python":
            config = generate_python_ruff_config(
                toolchain, target_dir, dry_run, existing_configs
            )
            if config:
                pyproject_path = target_dir / "pyproject.toml"
                if not dry_run:
                    if pyproject_path.exists():
                        # pyproject.toml があるが [tool.ruff] がない → 末尾に追記
                        existing_content = pyproject_path.read_text(encoding="utf-8")
                        separator = "\n" if existing_content.endswith("\n") else "\n\n"
                        pyproject_path.write_text(
                            existing_content + separator + config,
                            encoding="utf-8",
                        )
                    else:
                        pyproject_path.write_text(config, encoding="utf-8")
                generated_files.append("pyproject.toml [tool.ruff]")

    # CI コマンド
    ci_commands = generate_ci_commands(lang_names, registry)

    # 証跡ファイル
    evidence_path = generate_evidence_trail(
        detection,
        registry,
        generated_files,
        ci_commands,
        target_dir,
        template_dir,
        dry_run,
    )
    if evidence_path:
        generated_files.append(evidence_path)

    result: Dict[str, Any] = {
        "mode": mode,
        "languages": lang_names,
        "generated_files": generated_files,
        "ci_commands": ci_commands,
    }

    if proposals:
        result["proposals"] = proposals
    if existing_configs:
        result["existing_configs"] = existing_configs

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Linter設定を生成する")
    parser.add_argument(
        "detection_file",
        help="detect-languages.py の JSON 出力ファイル",
    )
    parser.add_argument(
        "--registry",
        default=None,
        help="lint-registry.json のパス（デフォルト: 自動検出）",
    )
    parser.add_argument(
        "--target-dir",
        default=".",
        help="設定ファイルの出力先ディレクトリ（デフォルト: カレントディレクトリ）",
    )
    parser.add_argument(
        "--template-dir",
        default=None,
        help="テンプレートディレクトリ（デフォルト: 自動検出）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="ファイルを生成せずプレビューのみ",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="結果をJSON形式で出力",
    )

    args = parser.parse_args()

    # レジストリファイルの解決
    if args.registry:
        registry_path = Path(args.registry)
    else:
        script_dir = Path(__file__).parent
        registry_path = script_dir / "lint-registry.json"

    registry = load_registry(registry_path)
    detection = load_detection_result(args.detection_file)
    target_dir = Path(args.target_dir).resolve()

    template_dir = Path(args.template_dir) if args.template_dir else None

    result = run_setup(detection, registry, target_dir, args.dry_run, template_dir)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if result.get("error"):
            return 1
    else:
        if result.get("error"):
            eprint(f"\n[ERROR] {result['error']}")
            return 1

        mode = result.get("mode", "generate")
        print(
            f"\n=== Linter セットアップ {'（プレビュー）' if args.dry_run else '完了'} ==="
        )
        print(f"モード: {mode}")
        print(f"検出言語: {', '.join(result.get('languages', []))}")

        if result.get("generated_files"):
            print("\n生成ファイル:")
            for f in result["generated_files"]:
                print(f"  - {f}")

        if result.get("proposals"):
            print("\n提案:")
            for p in result["proposals"]:
                print(p)

        if result.get("ci_commands"):
            print("\n推奨CIコマンド:")
            for cmd in result["ci_commands"]:
                print(f"  {cmd['key']}: {cmd['value']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
