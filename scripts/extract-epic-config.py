#!/usr/bin/env python3
"""
Epic情報抽出スクリプト

Epicファイルをパースして技術選定情報、Q6要件、API設計情報をJSON形式で出力する。
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def extract_section(text: str, section_pattern: str) -> Optional[str]:
    """指定されたセクションの内容を抽出する"""
    # セクションヘッダーから次のセクションヘッダーまでを抽出
    # section_pattern は「3.2 技術選定」のような形式を想定
    # Note: {{1,4}} はf-string内で {1,4} にエスケープされる
    pattern = rf"(#{{1,4}}\s*{section_pattern}.*?)(?=\n#{{1,4}}\s|\Z)"
    match = re.search(pattern, text, re.DOTALL)
    if match:
        return match.group(1).strip()
    return None


def extract_key_value_block(text: str, block_prefix: str) -> List[Dict[str, str]]:
    """
    技術選定-1, 技術選定-2 のようなブロックを抽出する

    形式:
    技術選定-1
    カテゴリ: 言語
    選択: TypeScript
    理由: ...
    """
    results = []
    pattern = rf"{block_prefix}-\d+\n((?:[^\n]+: [^\n]+\n?)+)"
    matches = re.findall(pattern, text)

    for match in matches:
        item = {}
        for line in match.strip().split("\n"):
            if ": " in line:
                key, value = line.split(": ", 1)
                item[key.strip()] = value.strip()
        if item:
            results.append(item)

    return results


def extract_tech_stack(text: str) -> Dict[str, Any]:
    """技術選定情報（セクション3.2）を抽出"""
    section = extract_section(text, r"3\.2\s+技術選定")
    if not section:
        return {}

    tech_items = extract_key_value_block(section, "技術選定")

    result = {
        "language": None,
        "framework": None,
        "database": None,
        "infrastructure": None,
        "raw": tech_items,
    }

    for item in tech_items:
        category = item.get("カテゴリ", "").lower()
        selection = item.get("選択", "")
        reason = item.get("理由", "")

        if category == "言語":
            result["language"] = {"name": selection, "reason": reason}
        elif category == "フレームワーク":
            result["framework"] = {"name": selection, "reason": reason}
        elif category in ["データベース", "db"]:
            result["database"] = {"name": selection, "reason": reason}
        elif category == "インフラ":
            result["infrastructure"] = {"name": selection, "reason": reason}

    return result


def extract_q6_requirements(text: str) -> Dict[str, Any]:
    """Q6要件（セクション5のプロダクション品質設計）を抽出"""
    result = {
        "security": False,
        "performance": False,
        "observability": False,
        "availability": False,
        "details": {},
    }

    # セキュリティ（Q6-5）
    security_section = extract_section(text, r"5\.2\s+セキュリティ設計")
    if security_section:
        # 行頭の「PRD Q6-X:」パターンを検索（ヘッダー内の「Yesの場合必須」を除外）
        q6_match = re.search(
            r"^PRD Q6-5:\s*(Yes|No)\s*$", security_section, re.IGNORECASE | re.MULTILINE
        )
        if q6_match and q6_match.group(1).lower() == "yes":
            result["security"] = True
            result["details"]["security"] = extract_security_details(security_section)

    # パフォーマンス（Q6-7）
    perf_section = extract_section(text, r"5\.1\s+パフォーマンス設計")
    if perf_section:
        q6_match = re.search(
            r"^PRD Q6-7:\s*(Yes|No)\s*$", perf_section, re.IGNORECASE | re.MULTILINE
        )
        if q6_match and q6_match.group(1).lower() == "yes":
            result["performance"] = True
            result["details"]["performance"] = extract_performance_details(perf_section)

    # 観測性（Q6-6）
    obs_section = extract_section(text, r"5\.3\s+観測性設計")
    if obs_section:
        q6_match = re.search(
            r"^PRD Q6-6:\s*(Yes|No)\s*$", obs_section, re.IGNORECASE | re.MULTILINE
        )
        if q6_match and q6_match.group(1).lower() == "yes":
            result["observability"] = True
            result["details"]["observability"] = extract_observability_details(
                obs_section
            )

    # 可用性（Q6-8）
    avail_section = extract_section(text, r"5\.4\s+可用性設計")
    if avail_section:
        q6_match = re.search(
            r"^PRD Q6-8:\s*(Yes|No)\s*$", avail_section, re.IGNORECASE | re.MULTILINE
        )
        if q6_match and q6_match.group(1).lower() == "yes":
            result["availability"] = True
            result["details"]["availability"] = extract_availability_details(
                avail_section
            )

    return result


def extract_security_details(section: str) -> Dict[str, Any]:
    """セキュリティセクションの詳細を抽出"""
    details = {
        "auth_method": None,
        "auth_expiry": None,
        "password_hash": None,
        "pii_list": [],
        "data_protection": [],
    }

    # 認証方式
    auth_match = re.search(r"認証方式:\s*\[?([^\]\n]+)\]?", section)
    if auth_match:
        details["auth_method"] = auth_match.group(1).strip()

    # 認可モデル
    authz_match = re.search(r"認可モデル:\s*\[?([^\]\n]+)\]?", section)
    if authz_match:
        details["authz_model"] = authz_match.group(1).strip()

    # 扱うデータ
    data_section = re.search(r"扱うデータ:\n((?:- [^\n]+\n?)+)", section)
    if data_section:
        for line in data_section.group(1).strip().split("\n"):
            line = line.strip("- ").strip()
            if ": " in line:
                data_type, protection = line.split(": ", 1)
                details["data_protection"].append(
                    {"type": data_type.strip(), "protection": protection.strip()}
                )
                # パスワードハッシュの検出
                if "パスワード" in data_type.lower():
                    hash_match = re.search(
                        r"(bcrypt|argon2|scrypt|pbkdf2)", protection.lower()
                    )
                    if hash_match:
                        details["password_hash"] = {"algorithm": hash_match.group(1)}
                # PIIの検出
                pii_keywords = [
                    "メール",
                    "email",
                    "名前",
                    "name",
                    "住所",
                    "address",
                    "電話",
                    "phone",
                ]
                if any(kw in data_type.lower() for kw in pii_keywords):
                    details["pii_list"].append(
                        {"name": data_type.strip(), "protection": protection.strip()}
                    )

    return details


def extract_performance_details(section: str) -> Dict[str, Any]:
    """パフォーマンスセクションの詳細を抽出"""
    details = {"targets": [], "measurement": {}, "bottlenecks": []}

    # 対象操作
    target_section = re.search(r"対象操作:\n((?:- [^\n]+\n?)+)", section)
    if target_section:
        for line in target_section.group(1).strip().split("\n"):
            line = line.strip("- ").strip()
            if ": " in line:
                operation, target = line.split(": ", 1)
                details["targets"].append(
                    {"operation": operation.strip(), "target": target.strip()}
                )

    # 測定方法
    tool_match = re.search(r"ツール:\s*\[?([^\]\n]+)\]?", section)
    if tool_match:
        details["measurement"]["tool"] = tool_match.group(1).strip()

    env_match = re.search(r"環境:\s*\[?([^\]\n]+)\]?", section)
    if env_match:
        details["measurement"]["environment"] = env_match.group(1).strip()

    return details


def extract_observability_details(section: str) -> Dict[str, Any]:
    """観測性セクションの詳細を抽出"""
    details = {"logging": {}, "metrics": [], "alerts": []}

    # ログ設定
    output_match = re.search(r"出力先:\s*\[?([^\]\n]+)\]?", section)
    if output_match:
        details["logging"]["output"] = output_match.group(1).strip()

    format_match = re.search(r"フォーマット:\s*\[?([^\]\n]+)\]?", section)
    if format_match:
        details["logging"]["format"] = format_match.group(1).strip()

    retention_match = re.search(r"保持期間:\s*\[?([^\]\n]+)\]?", section)
    if retention_match:
        details["logging"]["retention"] = retention_match.group(1).strip()

    return details


def extract_availability_details(section: str) -> Dict[str, Any]:
    """可用性セクションの詳細を抽出"""
    details = {"slo": {}, "recovery": {}, "rollback": {}}

    # SLO
    uptime_match = re.search(r"稼働率:\s*\[?([^\]\n]+)\]?", section)
    if uptime_match:
        details["slo"]["uptime"] = uptime_match.group(1).strip()

    # RTO/RPO
    rto_match = re.search(r"RTO:\s*\[?([^\]\n]+)\]?", section)
    if rto_match:
        details["recovery"]["rto"] = rto_match.group(1).strip()

    rpo_match = re.search(r"RPO:\s*\[?([^\]\n]+)\]?", section)
    if rpo_match:
        details["recovery"]["rpo"] = rpo_match.group(1).strip()

    return details


def extract_api_design(text: str) -> List[Dict[str, str]]:
    """API設計情報（セクション3.4）を抽出"""
    section = extract_section(text, r"3\.4\s+API設計")
    if not section:
        return []

    api_items = extract_key_value_block(section, "API")

    apis = []
    for item in api_items:
        endpoint = item.get("エンドポイント", "")
        if endpoint and endpoint != "[例: /api/users]":
            apis.append(
                {
                    "endpoint": endpoint,
                    "method": item.get("メソッド", ""),
                    "description": item.get("説明", ""),
                }
            )

    return apis


def extract_meta_info(text: str) -> Dict[str, str]:
    """メタ情報を抽出"""
    meta = {"prd_path": None, "created_date": None, "status": None}

    # 参照PRD
    prd_match = re.search(r"参照PRD:\s*`?([^`\n]+)`?", text)
    if prd_match:
        meta["prd_path"] = prd_match.group(1).strip()

    # 作成日
    date_match = re.search(r"作成日:\s*(\d{4}-\d{2}-\d{2})", text)
    if date_match:
        meta["created_date"] = date_match.group(1)

    # ステータス
    status_match = re.search(r"ステータス:\s*(Draft|Review|Approved)", text)
    if status_match:
        meta["status"] = status_match.group(1)

    return meta


def extract_epic_config(epic_path: str) -> Dict[str, Any]:
    """Epicファイルから設定情報を抽出"""
    text = read_text(epic_path)

    config = {
        "epic_path": epic_path,
        "meta": extract_meta_info(text),
        "tech_stack": extract_tech_stack(text),
        "requirements": extract_q6_requirements(text),
        "api_design": extract_api_design(text),
    }

    return config


def main() -> int:
    parser = argparse.ArgumentParser(description="Epic情報を抽出してJSON形式で出力")
    parser.add_argument("epic_file", help="Epicファイルのパス")
    parser.add_argument(
        "-o", "--output", help="出力ファイルのパス（指定しない場合は標準出力）"
    )
    parser.add_argument("--pretty", action="store_true", help="整形して出力")

    args = parser.parse_args()

    epic_path = Path(args.epic_file)
    if not epic_path.exists():
        eprint(f"Error: Epic file not found: {epic_path}")
        return 1

    try:
        config = extract_epic_config(str(epic_path))
    except Exception as e:
        eprint(f"Error: Failed to extract config: {e}")
        return 1

    indent = 2 if args.pretty else None
    output = json.dumps(config, ensure_ascii=False, indent=indent)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(output)
            fh.write("\n")
        eprint(f"Output written to: {args.output}")
    else:
        print(output)

    return 0


if __name__ == "__main__":
    sys.exit(main())
