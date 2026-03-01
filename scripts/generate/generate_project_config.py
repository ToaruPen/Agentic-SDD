#!/usr/bin/env python3
"""
プロジェクト固有スキル/ルール生成スクリプト

extract-epic-config.py の出力を受け取り、テンプレートに変数置換してファイルを生成する。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import argparse
import importlib
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

from _lib.subprocess_utils import run_cmd
from cli_utils import eprint

UTC_ATTR = "UTC"
UTC_TZ = getattr(datetime, UTC_ATTR, timezone(timedelta(0)))


class TemplateLike(Protocol):
    def render(self, **context: Any) -> str: ...


class JinjaEnvironmentLike(Protocol):
    def get_template(self, name: str) -> TemplateLike: ...


def find_repo_root() -> Path:
    """リポジトリのルートディレクトリを検出"""
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return Path.cwd()


def load_config(config_path: str) -> dict[str, Any]:
    """設定ファイルを読み込む"""
    return json.loads(Path(config_path).read_text(encoding="utf-8"))


def setup_jinja_env(template_dir: Path) -> JinjaEnvironmentLike:
    """Jinja2環境をセットアップ"""
    try:
        jinja2 = importlib.import_module("jinja2")
    except ImportError as exc:
        raise RuntimeError(
            "jinja2 is required. Install with: pip install jinja2"
        ) from exc

    return jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(template_dir)),
        autoescape=jinja2.select_autoescape(["html", "xml"]),
        trim_blocks=True,
        lstrip_blocks=True,
    )


def generate_config_json(
    env: JinjaEnvironmentLike,
    config: dict[str, Any],
    output_dir: Path,
    generated_skills: list[str],
    generated_rules: list[str],
) -> str:
    """config.json を生成"""
    template = env.get_template("config.json.j2")

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path"),
        "generated_at": datetime.now(UTC_TZ).isoformat(),
        "tech_stack": config.get("tech_stack", {}),
        "requirements": config.get("requirements", {}),
        "generated_skills": generated_skills,
        "generated_rules": generated_rules,
    }

    content = template.render(**context)
    output_path = output_dir / "config.json"
    output_path.write_text(content, encoding="utf-8")

    return str(output_path)


def generate_security_rules(
    env: JinjaEnvironmentLike,
    config: dict[str, Any],
    output_dir: Path,
) -> str | None:
    """セキュリティルールを生成"""
    requirements = config.get("requirements", {})
    if not requirements.get("security"):
        return None

    template = env.get_template("rules/security.md.j2")

    security_details = requirements.get("details", {}).get("security", {})

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path", ""),
        "security_details": security_details,
    }

    content = template.render(**context)
    output_path = output_dir / "rules" / "security.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")

    return str(output_path)


def generate_performance_rules(
    env: JinjaEnvironmentLike,
    config: dict[str, Any],
    output_dir: Path,
) -> str | None:
    """パフォーマンスルールを生成"""
    requirements = config.get("requirements", {})
    if not requirements.get("performance"):
        return None

    template = env.get_template("rules/performance.md.j2")

    performance_details = requirements.get("details", {}).get("performance", {})

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path", ""),
        "performance_details": performance_details,
    }

    content = template.render(**context)
    output_path = output_dir / "rules" / "performance.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")

    return str(output_path)


def generate_api_conventions(
    env: JinjaEnvironmentLike,
    config: dict[str, Any],
    output_dir: Path,
) -> str | None:
    """API規約を生成"""
    api_design = config.get("api_design", [])
    if not api_design:
        return None

    template = env.get_template("rules/api-conventions.md.j2")

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path", ""),
        "api_endpoints": api_design,
    }

    content = template.render(**context)
    output_path = output_dir / "rules" / "api-conventions.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")

    return str(output_path)


def generate_tech_stack_skill(
    env: JinjaEnvironmentLike,
    config: dict[str, Any],
    output_dir: Path,
) -> str | None:
    """技術スタックスキルを生成"""
    tech_stack = config.get("tech_stack", {})
    # 技術選定情報が1つでもあれば生成
    has_tech = any(
        [
            tech_stack.get("language"),
            tech_stack.get("framework"),
            tech_stack.get("database"),
            tech_stack.get("infrastructure"),
        ]
    )

    if not has_tech:
        return None

    template = env.get_template("skills/tech-stack.md.j2")

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path", ""),
        "tech_stack": tech_stack,
    }

    content = template.render(**context)
    output_path = output_dir / "skills" / "tech-stack.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")

    return str(output_path)


def generate_all(
    config: dict[str, Any],
    template_dir: Path,
    output_dir: Path,
    dry_run: bool = False,
) -> dict[str, Any]:
    """すべてのファイルを生成"""
    env = setup_jinja_env(template_dir)

    generated_skills: list[str] = []
    generated_rules: list[str] = []
    generated_files: list[str] = []

    # 出力ディレクトリを作成
    if not dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)

    # 技術スタックスキル
    if not dry_run:
        skill_path = generate_tech_stack_skill(env, config, output_dir)
        if skill_path:
            generated_skills.append("tech-stack.md")
            generated_files.append(skill_path)
    else:
        tech_stack = config.get("tech_stack", {})
        if any(
            [
                tech_stack.get("language"),
                tech_stack.get("framework"),
                tech_stack.get("database"),
                tech_stack.get("infrastructure"),
            ]
        ):
            generated_skills.append("tech-stack.md")

    # セキュリティルール
    if not dry_run:
        rule_path = generate_security_rules(env, config, output_dir)
        if rule_path:
            generated_rules.append("security.md")
            generated_files.append(rule_path)
    else:
        if config.get("requirements", {}).get("security"):
            generated_rules.append("security.md")

    # パフォーマンスルール
    if not dry_run:
        rule_path = generate_performance_rules(env, config, output_dir)
        if rule_path:
            generated_rules.append("performance.md")
            generated_files.append(rule_path)
    else:
        if config.get("requirements", {}).get("performance"):
            generated_rules.append("performance.md")

    # API規約
    if not dry_run:
        rule_path = generate_api_conventions(env, config, output_dir)
        if rule_path:
            generated_rules.append("api-conventions.md")
            generated_files.append(rule_path)
    else:
        if config.get("api_design"):
            generated_rules.append("api-conventions.md")

    # config.json を最後に生成（生成ファイル一覧を含めるため）
    if not dry_run:
        config_path = generate_config_json(
            env, config, output_dir, generated_skills, generated_rules
        )
        generated_files.insert(0, config_path)

    return {
        "output_dir": str(output_dir),
        "generated_skills": generated_skills,
        "generated_rules": generated_rules,
        "generated_files": generated_files,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="プロジェクト固有のスキル/ルールを生成"
    )
    parser.add_argument(
        "config_file",
        help="extract-epic-config.py の出力JSONファイル、またはEpicファイルのパス",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        default=".agentic-sdd/project",
        help="出力ディレクトリ（デフォルト: .agentic-sdd/project）",
    )
    parser.add_argument(
        "-t", "--template-dir", help="テンプレートディレクトリ（デフォルト: 自動検出）"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="実際にファイルを生成せず、生成予定のファイル一覧を表示",
    )
    parser.add_argument("--json", action="store_true", help="結果をJSON形式で出力")
    parser.add_argument(
        "--skip-lint",
        action="store_true",
        help="/lint-setup の自動実行をスキップ",
    )

    args = parser.parse_args()

    config_path = Path(args.config_file)
    if not config_path.exists():
        eprint(f"Error: Config file not found: {config_path}")
        return 1

    # JSONファイルかEpicファイルかを判定
    if config_path.suffix == ".json":
        try:
            config = load_config(str(config_path))
        except (json.JSONDecodeError, OSError) as exc:
            eprint(f"Error: Failed to load config: {exc}")
            return 1
    elif config_path.suffix == ".md":
        # Epicファイルの場合は extract-epic-config.py を呼び出す
        script_dir = Path(__file__).parent
        extract_script = script_dir.parent / "extract" / "extract_epic_config.py"

        if not extract_script.exists():
            extract_script = script_dir.parent / "extract-epic-config.py"

        if not extract_script.exists():
            eprint("Error: extract_epic_config.py not found")
            return 1

        proc = run_cmd(
            [sys.executable, str(extract_script), str(config_path)],
            check=False,
        )
        if proc.returncode != 0:
            eprint(f"Error: Failed to extract config: {proc.stderr}")
            return 1

        try:
            config = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            eprint(f"Error: Failed to parse extracted config: {exc}")
            return 1
    else:
        eprint(f"Error: Unsupported file type: {config_path.suffix}")
        return 1

    # テンプレートディレクトリを解決
    if args.template_dir:
        template_dir = Path(args.template_dir)
    else:
        # スクリプトの場所から相対パスで検索
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent.parent
        template_dir = repo_root / "templates" / "project-config"

        if not template_dir.exists():
            # カレントディレクトリからも検索
            template_dir = find_repo_root() / "templates" / "project-config"

    if not template_dir.exists():
        eprint(f"Error: Template directory not found: {template_dir}")
        return 1

    output_dir = Path(args.output_dir)

    try:
        result = generate_all(config, template_dir, output_dir, args.dry_run)
    except (OSError, RuntimeError, ValueError) as exc:
        eprint(f"Error: Failed to generate files: {exc}")
        return 1

    if not args.skip_lint:
        script_dir = Path(__file__).parent
        detect_script = script_dir.parent / "detect-languages.py"
        lint_script = script_dir.parent / "lint-setup.py"

        if detect_script.exists() and lint_script.exists():
            target = find_repo_root()
            detect_proc = run_cmd(
                [sys.executable, str(detect_script), "--path", str(target), "--json"],
                check=False,
            )
            if detect_proc.returncode == 0:
                import tempfile  # noqa: PLC0415

                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".json", delete=False
                ) as tmp:
                    tmp.write(detect_proc.stdout)
                    tmp_path = tmp.name

                try:
                    lint_args = [
                        sys.executable,
                        str(lint_script),
                        tmp_path,
                        "--output-dir",
                        str(output_dir),
                    ]
                    if args.dry_run:
                        lint_args.append("--dry-run")
                    lint_args.append("--json")

                    lint_proc = run_cmd(lint_args, check=False)

                    if lint_proc.returncode == 0:
                        try:
                            result["lint_setup"] = json.loads(lint_proc.stdout)
                        except (json.JSONDecodeError, ValueError) as exc:
                            eprint(
                                f"[WARN] lint-setup returned 0 but output is not valid JSON: {exc}"
                            )
                            result["lint_setup"] = None
                            result["lint_setup_error"] = f"invalid JSON output: {exc}"
                            result["lint_setup_stdout"] = lint_proc.stdout
                    else:
                        stderr = lint_proc.stderr.strip()
                        eprint(
                            f"[WARN] lint-setup failed (exit {lint_proc.returncode}): {stderr}"
                        )
                        result["lint_setup_error"] = (
                            stderr or f"exit code {lint_proc.returncode}"
                        )
                finally:
                    Path(tmp_path).unlink(missing_ok=True)
            else:
                eprint("[WARN] Language detection failed; skipping lint-setup")
                result["lint_setup_error"] = "Language detection failed"

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if args.dry_run:
            print("=== Dry Run: 生成予定のファイル ===")
        else:
            print("=== 生成完了 ===")

        print(f"\n出力ディレクトリ: {result['output_dir']}")

        if result["generated_skills"]:
            print("\nスキル:")
            for skill in result["generated_skills"]:
                print(f"  - skills/{skill}")

        if result["generated_rules"]:
            print("\nルール:")
            for rule in result["generated_rules"]:
                print(f"  - rules/{rule}")

        if not args.dry_run:
            print("\n生成ファイル一覧:")
            for f in result["generated_files"]:
                print(f"  - {f}")

        lint_result = result.get("lint_setup", {})
        recommendations = lint_result.get("recommendations", [])
        if recommendations:
            print("\nLinter推奨ツール:")
            for rec in recommendations:
                linter = rec.get("linter", {})
                print(
                    f"  - {rec['language']}: {linter.get('name')} ({linter.get('docs_url')})"
                )

        conflicts = lint_result.get("conflicts", [])
        if conflicts:
            print("\nLinter競合:")
            for conflict in conflicts:
                print(f"  - {conflict['language']}: {conflict['message']}")

    if result.get("lint_setup_error") and not args.skip_lint:
        eprint(
            f"[WARN] lint-setup failed: {result['lint_setup_error']}. "
            "Use --skip-lint to suppress this warning."
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
