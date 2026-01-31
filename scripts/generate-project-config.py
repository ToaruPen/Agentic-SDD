#!/usr/bin/env python3
"""
プロジェクト固有スキル/ルール生成スクリプト

extract-epic-config.py の出力を受け取り、テンプレートに変数置換してファイルを生成する。
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from jinja2 import Environment, FileSystemLoader, select_autoescape
except ImportError:
    print(
        "Error: jinja2 is required. Install with: pip install jinja2", file=sys.stderr
    )
    sys.exit(1)


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


def load_config(config_path: str) -> Dict[str, Any]:
    """設定ファイルを読み込む"""
    with open(config_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def setup_jinja_env(template_dir: Path) -> Environment:
    """Jinja2環境をセットアップ"""
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        autoescape=select_autoescape(["html", "xml"]),
        trim_blocks=True,
        lstrip_blocks=True,
    )
    return env


def generate_config_json(
    env: Environment,
    config: Dict[str, Any],
    output_dir: Path,
    generated_skills: List[str],
    generated_rules: List[str],
) -> str:
    """config.json を生成"""
    template = env.get_template("config.json.j2")

    context = {
        "epic_path": config.get("epic_path", ""),
        "prd_path": config.get("meta", {}).get("prd_path"),
        "generated_at": datetime.now().isoformat(),
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
    env: Environment,
    config: Dict[str, Any],
    output_dir: Path,
) -> Optional[str]:
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
    env: Environment,
    config: Dict[str, Any],
    output_dir: Path,
) -> Optional[str]:
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
    env: Environment,
    config: Dict[str, Any],
    output_dir: Path,
) -> Optional[str]:
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
    env: Environment,
    config: Dict[str, Any],
    output_dir: Path,
) -> Optional[str]:
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
    config: Dict[str, Any],
    template_dir: Path,
    output_dir: Path,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """すべてのファイルを生成"""
    env = setup_jinja_env(template_dir)

    generated_skills: List[str] = []
    generated_rules: List[str] = []
    generated_files: List[str] = []

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

    args = parser.parse_args()

    config_path = Path(args.config_file)
    if not config_path.exists():
        eprint(f"Error: Config file not found: {config_path}")
        return 1

    # JSONファイルかEpicファイルかを判定
    if config_path.suffix == ".json":
        config = load_config(str(config_path))
    elif config_path.suffix == ".md":
        # Epicファイルの場合は extract-epic-config.py を呼び出す
        import subprocess

        script_dir = Path(__file__).parent
        extract_script = script_dir / "extract-epic-config.py"

        if not extract_script.exists():
            eprint(f"Error: extract-epic-config.py not found at {extract_script}")
            return 1

        result = subprocess.run(
            [sys.executable, str(extract_script), str(config_path)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            eprint(f"Error: Failed to extract config: {result.stderr}")
            return 1

        config = json.loads(result.stdout)
    else:
        eprint(f"Error: Unsupported file type: {config_path.suffix}")
        return 1

    # テンプレートディレクトリを解決
    if args.template_dir:
        template_dir = Path(args.template_dir)
    else:
        # スクリプトの場所から相対パスで検索
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent
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
    except Exception as e:
        eprint(f"Error: Failed to generate files: {e}")
        return 1

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

    return 0


if __name__ == "__main__":
    sys.exit(main())
