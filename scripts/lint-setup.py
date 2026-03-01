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
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cli_utils import eprint  # noqa: E402


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
        try:
            return json.load(fh)
        except json.JSONDecodeError as exc:
            eprint(f"Error: Failed to parse registry JSON: {registry_path}: {exc}")
            sys.exit(1)


def load_detection_result(detection_path: str) -> Dict[str, Any]:
    """detect-languages.py の JSON 出力を読み込む"""
    path = Path(detection_path)
    if not path.exists():
        eprint(f"Error: Detection result file not found: {path}")
        sys.exit(1)
    with open(path, encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError as exc:
            eprint(f"Error: Failed to parse detection JSON: {path}: {exc}")
            sys.exit(1)


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
    existing_linters: List[str] = []
    for c in existing_configs:
        if not isinstance(c, dict):
            continue
        tool = c.get("tool")
        if tool and tool != recommended_linter:
            existing_linters.append(tool)

    linter_names = {recommended_linter} | set(existing_linters)
    conflict_groups = registry.get("conflict_groups", {})
    for group in conflict_groups.values():
        if language in group.get("languages", []):
            group_tools = set(group.get("tools", []))
            if len(linter_names & group_tools) > 1:
                return True
    return False


def lookup_toolchain(
    language: str,
    registry: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """レジストリから言語のツールチェーンを取得"""
    languages = registry.get("languages", {})
    return languages.get(language)


def _pick_ci_command(
    tool: Dict[str, Any],
    lang: str,
    lang_sources: Dict[str, List[str]],
) -> Optional[str]:
    """ビルドツール固有のCI コマンドがあれば優先する。"""
    sources = lang_sources.get(lang, [])
    gradle_sources = {"build.gradle", "build.gradle.kts"}
    if any(src in gradle_sources for src in sources):
        gradle_cmd = tool.get("ci_command_gradle")
        if gradle_cmd:
            return gradle_cmd
    return tool.get("ci_command")


def _pick_scoped_template(
    tool: Dict[str, Any],
    lang: str,
    lang_sources: Dict[str, List[str]],
) -> Optional[str]:
    sources = lang_sources.get(lang, [])
    gradle_sources = {"build.gradle", "build.gradle.kts"}
    if any(src in gradle_sources for src in sources):
        gradle_scoped = tool.get("ci_command_gradle_scoped")
        if gradle_scoped:
            return gradle_scoped
    return tool.get("ci_command_scoped")


def _scope_command(
    cmd: str,
    paths: List[str],
    scoped_template: Optional[str] = None,
) -> str:
    """CI コマンドをサブプロジェクトパスにスコーピングする。

    末尾 ' .' を持つコマンドのみパスで置換する。
    シェル構造を持つコマンド（サブシェル、パイプなど）を壊さないよう、
    末尾 ' .' 以外のコマンドには追記しない。
    """
    if not paths or set(paths) == {"."}:
        return cmd
    unique_paths = sorted(set(p for p in paths if p != "."))
    if not unique_paths:
        return cmd
    if scoped_template:
        return " && ".join(
            scoped_template.replace("{path}", shlex.quote(path))
            for path in unique_paths
        )

    path_args = " ".join(shlex.quote(p) for p in unique_paths)
    if cmd.endswith(" ."):
        return cmd[:-2] + " " + path_args
    return cmd


def generate_ci_commands(
    languages: List[str],
    registry: Dict[str, Any],
    lang_sources: Optional[Dict[str, List[str]]] = None,
    lang_paths: Optional[Dict[str, List[str]]] = None,
) -> List[Dict[str, str]]:
    """CI 推奨コマンドを生成（複数言語時は && で連結）"""
    if lang_sources is None:
        lang_sources = {}
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
        paths = lang_paths.get(lang, ["."]) if lang_paths else ["."]

        lint_cmd = _pick_ci_command(linter, lang, lang_sources)
        lint_scoped_template = _pick_scoped_template(linter, lang, lang_sources)
        if lint_cmd:
            lint_cmd = _scope_command(lint_cmd, paths, lint_scoped_template)
        if lint_cmd and lint_cmd not in lint_cmds:
            lint_cmds.append(lint_cmd)

        fmt_cmd = _pick_ci_command(formatter, lang, lang_sources)
        fmt_scoped_template = _pick_scoped_template(formatter, lang, lang_sources)
        if fmt_cmd:
            fmt_cmd = _scope_command(fmt_cmd, paths, fmt_scoped_template)
        if fmt_cmd and fmt_cmd not in fmt_cmds:
            fmt_cmds.append(fmt_cmd)

        tc_cmd = _pick_ci_command(type_checker, lang, lang_sources)
        tc_scoped_template = _pick_scoped_template(type_checker, lang, lang_sources)
        if tc_cmd:
            tc_cmd = _scope_command(tc_cmd, paths, tc_scoped_template)
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


def _build_toolchains(
    detection: Dict[str, Any],
    registry: Dict[str, Any],
) -> tuple[list[Dict[str, Any]], list[Dict[str, str]]]:
    """証跡用ツールチェーンデータを構築。(toolchains, existing_configs) を返す。"""
    languages = detection.get("languages", [])
    existing_configs = detection.get("existing_linter_configs", [])

    toolchains: list[Dict[str, Any]] = []
    for lang_info in languages:
        if not isinstance(lang_info, dict) or "name" not in lang_info:
            eprint(f"[WARN] malformed language entry skipped: {lang_info!r}")
            continue
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
    return toolchains, existing_configs


def _render_evidence_plaintext(
    context: Dict[str, Any],
) -> str:
    """証跡 Markdown を jinja2 なしで生成（フォールバック）。"""
    lines: List[str] = [
        "# Linter設定 証跡",
        "",
        "> このファイルは `/lint-setup` コマンドにより自動生成されました。",
        "",
        "## 生成情報",
        "",
        f"- 生成日時: {context['generated_at']}",
        f"- 対象ディレクトリ: {context['target_path']}",
        "",
        "## 検出された言語",
        "",
    ]
    for lang in context.get("languages", []):
        if not isinstance(lang, dict):
            continue
        name = lang.get("name", "unknown")
        source = lang.get("source", "unknown")
        path = lang.get("path", ".")
        lines.append(f"- **{name}** (検出元: `{source}`, パス: `{path}`)")
    lines.append("")
    lines.append("## 選定されたツールチェーン")
    lines.append("")
    for tc in context.get("toolchains", []):
        lines.append(f"### {tc['language']}")
        lines.append("")
        lines.append("| 種別 | ツール | 公式ドキュメント |")
        lines.append("|------|--------|-----------------|")
        lines.append(f"| Linter | {tc['linter_name']} | {tc['linter_docs_url']} |")
        lines.append(
            f"| Formatter | {tc['formatter_name']} | {tc['formatter_docs_url']} |"
        )
        if tc.get("type_checker_name"):
            lines.append(
                f"| Type Checker | {tc['type_checker_name']} | {tc['type_checker_docs_url']} |"
            )
        lines.append("")
        lines.append("**参照した公式ドキュメント:**")
        for ref in tc.get("references", []):
            lines.append(f"- {ref['url']} (証跡生成日時: {ref['registered_at']})")
        lines.append("")
        lines.append("**適用ルール分類:**")
        lines.append(f"- Essential: {', '.join(tc.get('essential_rules', []))}")
        if tc.get("recommended_rules"):
            lines.append(f"- Recommended: {', '.join(tc['recommended_rules'])}")
        if tc.get("conflict_exclusions"):
            lines.append("")
            lines.append("**フォーマッタ競合除外:**")
            lines.append(f"- {', '.join(tc['conflict_exclusions'])}")
        lines.append("")
    lines.append("## 既存設定との関係")
    lines.append("")
    existing = context.get("existing_configs", [])
    if existing:
        lines.append("以下の既存 linter 設定を検出しました（上書き不可）:")
        lines.append("")
        for cfg in existing:
            if not isinstance(cfg, dict):
                continue
            lines.append(f"- `{cfg.get('path', 'N/A')}` ({cfg.get('tool', 'unknown')})")
    else:
        lines.append("既存の linter 設定は検出されませんでした。")
    lines.append("")
    lines.append("## エージェント生成ファイル")
    lines.append("")
    lines.append("このスクリプトは推奨出力のみを行います。")
    lines.append(
        "実際の設定ファイルはエージェントがユーザーの希望と公式ドキュメントに基づいて動的に生成します。"
    )
    lines.append("")
    lines.append("## 推奨CIコマンド")
    lines.append("")
    lines.append("```bash")
    for cmd in context.get("ci_commands", []):
        lines.append(f'export {cmd["key"]}="{cmd["value"]}"')
    lines.append("```")
    return "\n".join(lines) + "\n"


def generate_evidence_trail(
    detection: Dict[str, Any],
    registry: Dict[str, Any],
    ci_commands: List[Dict[str, str]],
    target_dir: Path,
    output_dir_override: Optional[Path] = None,
    template_dir: Optional[Path] = None,
    dry_run: bool = False,
) -> Optional[str]:
    """証跡ファイル (.agentic-sdd/project/rules/lint.md) を生成。jinja2 がなければプレーンテキストでフォールバック。"""
    toolchains, existing_configs = _build_toolchains(detection, registry)

    context: Dict[str, Any] = {
        "generated_at": datetime.now(tz=timezone.utc).isoformat(),
        "target_path": str(target_dir),
        "languages": detection.get("languages", []),
        "toolchains": toolchains,
        "existing_configs": existing_configs,
        "generated_files": [],
        "ci_commands": ci_commands,
    }

    # jinja2 でレンダリングを試み、失敗時はプレーンテキストでフォールバック
    content: Optional[str] = None
    try:
        import importlib

        jinja2 = importlib.import_module("jinja2")
        Environment = jinja2.Environment
        FileSystemLoader = jinja2.FileSystemLoader

        if template_dir is None:
            script_dir = Path(__file__).parent
            repo_root = script_dir.parent
            template_dir = repo_root / "templates" / "project-config"

        if template_dir.exists():
            env = Environment(
                loader=FileSystemLoader(str(template_dir)),
                trim_blocks=True,
                lstrip_blocks=True,
                autoescape=False,  # noqa: S701 -- Markdown template, no XSS risk
            )
            template = env.get_template("rules/lint.md.j2")
            content = template.render(**context)
        else:
            eprint(
                f"[WARN] Template directory not found: {template_dir}; using plaintext fallback"
            )
    except ImportError:
        eprint(
            "[INFO] jinja2 not available; using plaintext fallback for evidence trail"
        )
    except Exception as exc:  # noqa: BLE001 -- template load/render failure should fall back
        eprint(f"[WARN] jinja2 template error: {exc}; using plaintext fallback")

    if content is None:
        content = _render_evidence_plaintext(context)

    if output_dir_override is not None:
        output_dir = output_dir_override / "rules"
    else:
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
    output_dir_override: Optional[Path] = None,
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

    # 言語名リスト（重複排除、順序維持）とパス情報の収集
    # confidence フィールドで確定検出と推測検出を区別する
    seen: set[str] = set()
    unique_lang_names: List[str] = []
    inferred_lang_names: List[str] = []
    lang_paths: Dict[str, List[str]] = {}
    lang_sources: Dict[str, List[str]] = {}  # 検出ソースファイル名を記録
    for lang in languages:
        if not isinstance(lang, dict) or "name" not in lang:
            eprint(f"[WARN] malformed language entry skipped: {lang!r}")
            continue
        name = lang["name"]
        path = lang.get("path", ".")
        source = lang.get("source", "")
        confidence = lang.get("confidence", "confirmed")
        if confidence == "inferred":
            if name not in seen and name not in inferred_lang_names:
                inferred_lang_names.append(name)
            lang_paths.setdefault(name, []).append(path)
            lang_sources.setdefault(name, []).append(source)
            continue
        if name not in seen:
            seen.add(name)
            unique_lang_names.append(name)
        lang_paths.setdefault(name, []).append(path)
        lang_sources.setdefault(name, []).append(source)

    if not unique_lang_names:
        eprint("[ERROR] 確定検出の言語がありません（推測のみ）。")
        early_result: Dict[str, Any] = {"error": "no_confirmed_languages"}
        if inferred_lang_names:
            early_result["inferred_languages"] = [
                {
                    "name": name,
                    "paths": sorted(set(lang_paths.get(name, ["."]))),
                    "note": "Inferred from build file; confirm with source files before configuring linter.",
                }
                for name in inferred_lang_names
            ]
        return early_result

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
            "paths": sorted(set(lang_paths.get(lang_name, ["."]))),
            "linter": {
                "name": linter.get("name"),
                "docs_url": linter.get("docs_url"),
                "config_file": linter.get("config_file"),
                "essential_rules": linter.get("essential_rules", []),
                "recommended_rules": linter.get("recommended_rules", []),
                "ci_command": _pick_ci_command(linter, lang_name, lang_sources),
            },
            "formatter": {
                "name": formatter.get("name"),
                "docs_url": formatter.get("docs_url"),
                "ci_command": _pick_ci_command(formatter, lang_name, lang_sources),
            },
        }

        tc_name = type_checker.get("name")
        if tc_name:
            rec["type_checker"] = {
                "name": tc_name,
                "docs_url": type_checker.get("docs_url"),
                "ci_command": _pick_ci_command(type_checker, lang_name, lang_sources),
            }

        # フレームワーク固有ルール
        framework_rules = toolchain.get("framework_rules", {})
        if framework_rules:
            rec["framework_rules"] = framework_rules

        recommendations.append(rec)

    # CI コマンド
    ci_commands = generate_ci_commands(
        unique_lang_names, registry, lang_sources, lang_paths
    )

    # 証跡ファイル（確定検出のみ）
    confirmed_languages = [
        lang
        for lang in languages
        if isinstance(lang, dict)
        and "name" in lang
        and lang.get("confidence", "confirmed") != "inferred"
    ]
    confirmed_detection: Dict[str, Any] = {
        **detection,
        "languages": confirmed_languages,
    }
    evidence_path = generate_evidence_trail(
        confirmed_detection,
        registry,
        ci_commands,
        target_dir,
        output_dir_override,
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
    # confirmed で確定した言語は inferred リストから除外する
    inferred_only = [n for n in inferred_lang_names if n not in seen]
    if inferred_only:
        # 推測検出の言語はシグナルとして保持（推奨には含めない）
        result["inferred_languages"] = [
            {
                "name": name,
                "paths": sorted(set(lang_paths.get(name, ["."]))),
                "note": "Inferred from build file; confirm with source files before configuring linter.",
            }
            for name in inferred_only
        ]

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
    output_group = parser.add_mutually_exclusive_group()
    output_group.add_argument(
        "--target-dir",
        default=".",
        help="証跡ファイルの出力先基準ディレクトリ（デフォルト: カレントディレクトリ）",
    )
    output_group.add_argument(
        "--output-dir",
        default=None,
        help="証跡ファイルの直接出力先（<output-dir>/rules/lint.md）",
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
    output_dir_override = (
        Path(args.output_dir).resolve() if args.output_dir is not None else None
    )

    template_dir = Path(args.template_dir) if args.template_dir else None

    result = run_setup(
        detection,
        registry,
        target_dir,
        args.dry_run,
        template_dir,
        output_dir_override,
    )

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
