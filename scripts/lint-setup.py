#!/usr/bin/env python3
"""
Linter推奨出力スクリプト

detect-languages.py の出力と lint-registry.json を組み合わせて、
推奨 linter ツールチェーンと公式ドキュメントURLを出力する。

設定ファイルの生成はエージェントが公式ドキュメントを調査した上で実施する。
このスクリプトはファイル書き込みを行わない（証跡ファイルのみ例外）。
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


def generate_ci_commands(
    languages: List[str],
    registry: Dict[str, Any],
) -> List[Dict[str, str]]:
    """CI 推奨コマンドを生成（複数言語時は && で連結）"""
    lint_cmds: List[str] = []
    fmt_cmds: List[str] = []
    tc_cmds: List[str] = []

    for lang in languages:
        toolchain = lookup_toolchain(lang, registry)
        if not toolchain:
            continue

        linter = toolchain.get("linter", {})
        formatter = toolchain.get("formatter", {})
        type_checker = toolchain.get("type_checker", {})

        lint_cmd = linter.get("ci_command")
        if lint_cmd and lint_cmd not in lint_cmds:
            lint_cmds.append(lint_cmd)

        fmt_cmd = formatter.get("ci_command")
        if fmt_cmd and fmt_cmd not in fmt_cmds:
            fmt_cmds.append(fmt_cmd)

        tc_cmd = type_checker.get("ci_command")
        if tc_cmd and tc_cmd not in tc_cmds:
            tc_cmds.append(tc_cmd)

    commands: List[Dict[str, str]] = []
    if lint_cmds:
        commands.append(
            {"key": "AGENTIC_SDD_CI_LINT_CMD", "value": " && ".join(lint_cmds)}
        )
    if fmt_cmds:
        commands.append(
            {"key": "AGENTIC_SDD_CI_FORMAT_CMD", "value": " && ".join(fmt_cmds)}
        )
    if tc_cmds:
        commands.append(
            {"key": "AGENTIC_SDD_CI_TYPECHECK_CMD", "value": " && ".join(tc_cmds)}
        )

    return commands


def generate_evidence_trail(
    detection: Dict[str, Any],
    registry: Dict[str, Any],
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
        "generated_files": [],
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
    """メインのセットアップ処理 — 推奨出力のみ（設定ファイル書き込みなし）"""
    if not target_dir.is_dir():
        eprint(
            f"[ERROR] target-dir が存在しないか、ディレクトリではありません: {target_dir}"
        )
        return {"error": "invalid_target_dir"}

    languages = detection.get("languages", [])
    existing_configs = detection.get("existing_linter_configs", [])

    if not languages:
        eprint("[ERROR] 言語を検出できませんでした。")
        return {"error": "no_languages_detected"}

    # 言語名リスト（重複排除、順序維持）
    seen: set[str] = set()
    unique_lang_names: List[str] = []
    for lang in languages:
        name = lang["name"]
        if name not in seen:
            seen.add(name)
            unique_lang_names.append(name)

    # 各言語の推奨ツールチェーンを構築
    recommendations: List[Dict[str, Any]] = []
    conflicts: List[Dict[str, Any]] = []

    for lang_name in unique_lang_names:
        toolchain = lookup_toolchain(lang_name, registry)
        if not toolchain:
            eprint(
                f"[WARN] レジストリに未登録の言語を検出: {lang_name}。手動での linter 設定が必要です。"
            )
            continue

        # 競合チェック
        if has_conflicting_tools(existing_configs, lang_name, registry):
            conflicts.append(
                {
                    "language": lang_name,
                    "message": "複数の競合する linter 設定を検出しました。",
                }
            )

        linter = toolchain.get("linter", {})
        formatter = toolchain.get("formatter", {})
        type_checker = toolchain.get("type_checker", {})

        rec: Dict[str, Any] = {
            "language": lang_name,
            "linter": {
                "name": linter.get("name"),
                "docs_url": linter.get("docs_url"),
                "config_file": linter.get("config_file"),
                "essential_rules": linter.get("essential_rules", []),
                "recommended_rules": linter.get("recommended_rules", []),
                "ci_command": linter.get("ci_command"),
            },
            "formatter": {
                "name": formatter.get("name"),
                "docs_url": formatter.get("docs_url"),
                "ci_command": formatter.get("ci_command"),
            },
        }

        tc_name = type_checker.get("name")
        if tc_name:
            rec["type_checker"] = {
                "name": tc_name,
                "docs_url": type_checker.get("docs_url"),
                "ci_command": type_checker.get("ci_command"),
            }

        # フレームワーク固有ルール
        framework_rules = toolchain.get("framework_rules", {})
        if framework_rules:
            rec["framework_rules"] = framework_rules

        recommendations.append(rec)

    # CI コマンド
    ci_commands = generate_ci_commands(unique_lang_names, registry)

    # 証跡ファイル
    evidence_path = generate_evidence_trail(
        detection,
        registry,
        ci_commands,
        target_dir,
        template_dir,
        dry_run,
    )

    result: Dict[str, Any] = {
        "languages": unique_lang_names,
        "recommendations": recommendations,
        "ci_commands": ci_commands,
    }

    if existing_configs:
        result["existing_configs"] = existing_configs
    if conflicts:
        result["conflicts"] = conflicts
    if evidence_path and not dry_run:
        result["evidence_trail"] = evidence_path

    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="検出された言語に対する推奨 linter ツールチェーンを出力する"
    )
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
        help="証跡ファイルの出力先ディレクトリ（デフォルト: カレントディレクトリ）",
    )
    parser.add_argument(
        "--template-dir",
        default=None,
        help="テンプレートディレクトリ（デフォルト: 自動検出）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="証跡ファイルを生成せずプレビューのみ",
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

        print("\n=== Linter 推奨ツールチェーン ===")
        print(f"検出言語: {', '.join(result.get('languages', []))}")

        if result.get("recommendations"):
            print("\n推奨ツール:")
            for rec in result["recommendations"]:
                linter = rec.get("linter", {})
                print(f"  {rec['language']}:")
                print(f"    Linter: {linter.get('name')} ({linter.get('docs_url')})")
                fmt = rec.get("formatter", {})
                if fmt.get("name"):
                    print(f"    Formatter: {fmt.get('name')} ({fmt.get('docs_url')})")
                tc = rec.get("type_checker", {})
                if tc and tc.get("name"):
                    print(f"    Type Checker: {tc.get('name')} ({tc.get('docs_url')})")

        if result.get("existing_configs"):
            print("\n既存設定（上書き不可）:")
            for config in result["existing_configs"]:
                print(f"  - {config.get('path')} ({config.get('tool')})")

        if result.get("conflicts"):
            print("\n競合検出:")
            for conflict in result["conflicts"]:
                print(f"  - {conflict['language']}: {conflict['message']}")

        if result.get("ci_commands"):
            print("\n推奨CIコマンド:")
            for cmd in result["ci_commands"]:
                print(f"  {cmd['key']}: {cmd['value']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
