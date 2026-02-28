#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional

from md_sanitize import (
    sanitize_status_text,
    strip_fenced_code_blocks,
    strip_html_comment_blocks,
    strip_indented_code_blocks,
)


@dataclass(frozen=True)
class LintError:
    path: str
    message: str


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def repo_root() -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        return os.path.realpath(os.getcwd())

    try:
        p = subprocess.run(  # noqa: S603
            [git_bin, "rev-parse", "--show-toplevel"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,  # noqa: S603
        )
    except Exception:
        return os.path.realpath(os.getcwd())

    root = (p.stdout or "").strip()
    if not root:
        return os.path.realpath(os.getcwd())
    return os.path.realpath(root)


def iter_markdown_files(root: str) -> Iterable[str]:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".agentic-sdd"}]
        dirnames.sort()
        filenames.sort()
        for name in filenames:
            if not name.endswith(".md"):
                continue
            yield os.path.join(dirpath, name)


def is_safe_repo_relative_root(root: str) -> bool:
    if not root:
        return False
    if os.path.isabs(root):
        return False
    p = root.replace("\\", "/").strip()
    if p.startswith("./"):
        p = p[2:]
    if p in {".", ".."}:
        return False
    parts = [x for x in p.split("/") if x]
    if not parts:
        return False
    if ".." in parts:
        return False
    return True


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


_STATUS_APPROVED_RE = re.compile(r"^\s*-\s*ステータス\s*:\s*Approved\s*$", re.MULTILINE)
_STATUS_ANY_RE = re.compile(r"^\s*-\s*ステータス\s*:\s*\S", re.MULTILINE)
_ALLOW_HTML_COMMENTS_RE = re.compile(r"<!--\s*lint-sot:\s*allow-html-comments\s*-->")
_SOT_REFERENCE_PRD_LINE_RE = re.compile(
    r"^\s*-\s*参照PRD[ \t]*:[ \t]*(?:`([^`\n]*)`|([^\n]*))[ \t]*$", re.MULTILINE
)


_RESEARCH_CANDIDATE_BLOCK_RE = re.compile(
    r"^\s*候補-(\d+)\s*$.*?(?=^\s*候補-\d+\s*$|^\s*#{1,6}\s|^\s*---\s*$|\Z)",
    re.MULTILINE | re.DOTALL,
)
_RESEARCH_ADJACENT_RE = re.compile(r"^\s*隣接領域-(\d+)\s*$", re.MULTILINE)
_RESEARCH_ABSTRACTION_RE = re.compile(r"^\s*抽象化-(\d+)\s*$", re.MULTILINE)
_RESEARCH_NOVELTY_YES_BULLET_RE = re.compile(
    r"^\s*-\s*(.+?)\s*:\s*Yes\s*$", re.MULTILINE
)
_RESEARCH_NOVELTY_H2_RE = re.compile(
    r"^\s*##\s*(?:\d+\.\s*)?新規性判定（発火条件）\s*$", re.MULTILINE
)
_RESEARCH_ADJACENT_H2_RE = re.compile(
    r"^\s*##\s*(?:\d+\.\s*)?隣接領域探索.*$", re.MULTILINE
)
_RESEARCH_ANY_H2_RE = re.compile(r"^\s*##\s+", re.MULTILINE)
_RESEARCH_EVIDENCE_URL_RE = re.compile(r"^\s*-\s*https?://\S+", re.MULTILINE)
_RESEARCH_APPLICABILITY_RE = re.compile(
    r"^\s*適用可否:[ \t]*(Yes|Partial|No)[ \t]*$", re.MULTILINE
)
_RESEARCH_CANDIDATE_REQUIRED_LABELS = [
    "概要:",
    "適用可否:",
    "仮説:",
    "反証:",
    "採否理由:",
    "根拠リンク:",
    "捨て条件:",
    "リスク/検証:",
]
_RESEARCH_NOVELTY_REQUIRED_SUBSTRINGS = [
    "直接の先行事例が2件未満",
    "Unknown",
    "Q6-5",
    "PII",
    "監査",
    "性能",
    "可用性",
]

_RESEARCH_NOVELTY_REQUIRED_TRIGGER_SUBSTRINGS = [
    "直接の先行事例が2件未満",
    "Unknown",
    "Q6-5",
]

_RESEARCH_EPIC_COMPARISON_H2_RE = re.compile(
    r"^\s*##\s*(?:\d+\.\s*)?外部サービス比較ゲート.*$", re.MULTILINE
)
_RESEARCH_EPIC_GATE_REQUIRED_RE = re.compile(
    r"^\s*外部サービス比較ゲート:\s*Required\s*$", re.MULTILINE
)
_RESEARCH_EPIC_GATE_SKIP_RE = re.compile(
    r"^\s*外部サービス比較ゲート:\s*Skip（[^）\n]+）\s*$", re.MULTILINE
)
_RESEARCH_EPIC_SERVICE_BULLET_RE = re.compile(
    r"^\s*-\s*[^（\n]+（[^）\n]+）\s*$", re.MULTILINE
)
_RESEARCH_EPIC_WEIGHT_BULLET_RE = re.compile(
    r"^\s*-\s*.+（\d{1,3}%）\s*$", re.MULTILINE
)

_RESEARCH_EPIC_REQUIRED_TABLE_COLUMNS = [
    "サービス名",
    "ベンダー",
    "初期費用",
    "月額費用",
    "レイテンシ",
    "可用性SLO",
    "運用負荷",
    "適用判定",
]


def _unique_ints(ms: Iterable[re.Match[str]]) -> List[int]:
    out: List[int] = []
    seen = set()
    for m in ms:
        v = None
        try:
            v = int(m.group(1))
        except (TypeError, ValueError, IndexError):
            v = None
        if v is None:
            continue
        if v in seen:
            continue
        seen.add(v)
        out.append(v)
    out.sort()
    return out


def extract_h2_section(text: str, heading_re: re.Pattern[str]) -> str:
    m = heading_re.search(text)
    if not m:
        return ""
    start = m.end()
    m_next = _RESEARCH_ANY_H2_RE.search(text, start)
    end = m_next.start() if m_next else len(text)
    return text[start:end]


def is_research_adjacent_exploration_required(text: str) -> bool:
    novelty = extract_h2_section(text, _RESEARCH_NOVELTY_H2_RE)
    for m in _RESEARCH_NOVELTY_YES_BULLET_RE.finditer(novelty):
        item = m.group(1)
        if any(s in item for s in _RESEARCH_NOVELTY_REQUIRED_SUBSTRINGS):
            return True
    return False


def has_candidate_evidence_url(block: str) -> bool:
    in_evidence = False
    for line in block.splitlines():
        s = line.strip()
        if not in_evidence:
            if s.startswith("根拠リンク:"):
                in_evidence = True
            continue

        if any(s.startswith(x) for x in _RESEARCH_CANDIDATE_REQUIRED_LABELS):
            if not s.startswith("根拠リンク:"):
                break

        if _RESEARCH_EVIDENCE_URL_RE.search(line):
            return True
    return False


def extract_labeled_block(section: str, start_label: str, end_labels: List[str]) -> str:
    in_block = False
    out: List[str] = []
    for line in section.splitlines():
        s = line.strip()
        if not in_block:
            if s == start_label:
                in_block = True
            continue

        if s in end_labels:
            break
        out.append(line)
    return "\n".join(out)


def count_markdown_table_rows_with_headers(
    section: str, required_headers: List[str]
) -> int:
    def parse_table_cells(row: str) -> List[str]:
        s = row.strip()
        body = s[1:]
        if body.endswith("|"):
            body = body[:-1]
        return [c.strip() for c in body.split("|")]

    lines = section.splitlines()
    for i, line in enumerate(lines):
        s = line.strip()
        if not s.startswith("|"):
            continue

        header_cells = parse_table_cells(s)
        if not all(h in header_cells for h in required_headers):
            continue

        count = 0
        expected_cols = len(header_cells)
        j = i + 1
        while j < len(lines):
            t = lines[j].strip()
            if not t.startswith("|"):
                break
            if re.fullmatch(r"\|\s*[-:| ]+\|?\s*", t):
                j += 1
                continue

            row_cells = parse_table_cells(t)
            if len(row_cells) != expected_cols:
                j += 1
                continue

            count += 1
            j += 1
        return count
    return -1


def lint_epic_external_service_comparison(
    rel_path: str, contract_text: str
) -> List[LintError]:
    errs: List[LintError] = []
    section = extract_h2_section(contract_text, _RESEARCH_EPIC_COMPARISON_H2_RE)
    if not section.strip():
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "Epic調査ドキュメントには見出し '## 外部サービス比較ゲート'（番号は任意）を含めてください"
                ),
            )
        )
        return errs

    has_required = _RESEARCH_EPIC_GATE_REQUIRED_RE.search(section) is not None
    has_skip = _RESEARCH_EPIC_GATE_SKIP_RE.search(section) is not None

    if has_required and has_skip:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートは 'Required' と 'Skip（理由）' のどちらか一方のみ記載してください"
                ),
            )
        )
        return errs

    if (not has_required) and (not has_skip):
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートには '外部サービス比較ゲート: Required' または "
                    "'外部サービス比較ゲート: Skip（理由）' を記載してください"
                ),
            )
        )
        return errs

    if has_skip:
        return errs

    labels = [
        "比較対象サービス:",
        "代替系統カバレッジ:",
        "評価軸（重み）:",
        "定量比較表:",
        "判定理由:",
    ]
    for label in labels:
        if re.search(rf"^\s*{re.escape(label)}\s*$", section, re.MULTILINE) is None:
            errs.append(
                LintError(
                    path=rel_path,
                    message=f"外部サービス比較ゲートに '{label}' がありません",
                )
            )

    service_block = extract_labeled_block(
        section,
        start_label="比較対象サービス:",
        end_labels=[
            "代替系統カバレッジ:",
            "評価軸（重み）:",
            "定量比較表:",
            "判定理由:",
        ],
    )
    service_count = len(_RESEARCH_EPIC_SERVICE_BULLET_RE.findall(service_block))
    if service_count < 3:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートの '比較対象サービス:' は 3件以上必要です。 "
                    "各行を '- サービス名（ベンダー名）' 形式で記載してください"
                ),
            )
        )

    family_block = extract_labeled_block(
        section,
        start_label="代替系統カバレッジ:",
        end_labels=["評価軸（重み）:", "定量比較表:", "判定理由:"],
    )
    family_count = len(re.findall(r"^\s*-\s+.+$", family_block, re.MULTILINE))
    if family_count < 3:
        errs.append(
            LintError(
                path=rel_path,
                message="外部サービス比較ゲートの '代替系統カバレッジ:' は 3件以上必要です",
            )
        )

    weight_block = extract_labeled_block(
        section,
        start_label="評価軸（重み）:",
        end_labels=["定量比較表:", "判定理由:"],
    )
    weight_count = len(_RESEARCH_EPIC_WEIGHT_BULLET_RE.findall(weight_block))
    if weight_count < 3:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートの '評価軸（重み）:' は 3件以上必要です。 "
                    "各行を '- 評価軸（NN%）' 形式で記載してください"
                ),
            )
        )

    table_block = extract_labeled_block(
        section,
        start_label="定量比較表:",
        end_labels=["判定理由:"],
    )
    table_rows = count_markdown_table_rows_with_headers(
        table_block, _RESEARCH_EPIC_REQUIRED_TABLE_COLUMNS
    )
    if table_rows == -1:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートの '定量比較表:' に必須列がありません。 "
                    "必須列: サービス名 / ベンダー / 初期費用 / 月額費用 / レイテンシ / "
                    "可用性SLO / 運用負荷 / 適用判定"
                ),
            )
        )
    elif table_rows < 3:
        errs.append(
            LintError(
                path=rel_path,
                message="外部サービス比較ゲートの '定量比較表:' は 3行以上のデータ行が必要です",
            )
        )

    reason_block = extract_labeled_block(
        section,
        start_label="判定理由:",
        end_labels=[],
    )
    if re.search(r"^\s*-\s+.+$", reason_block, re.MULTILINE) is None:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "外部サービス比較ゲートの '判定理由:' は 1件以上必要です。 "
                    "各行を '- 理由' 形式で記載してください"
                ),
            )
        )

    return errs


def is_approved_prd_or_epic(rel_path: str, text: str) -> bool:
    if rel_path.startswith("docs/prd/") or rel_path.startswith("docs/epics/"):
        if os.path.basename(rel_path) == "_template.md":
            return False
        status_text = sanitize_status_text(text)
        return _STATUS_APPROVED_RE.search(status_text) is not None
    return False


def lint_status_format(rel_path: str, text: str) -> List[LintError]:
    """Detect status lines lost during indented code block stripping.

    If a ステータス line exists after fenced/HTML-comment stripping but
    disappears after indented-code-block stripping, the status is likely
    in a nested list (4+ spaces) which our sanitizer cannot distinguish
    from indented code blocks.  Emit an explicit error instead of
    silently skipping Approved-only checks.
    """
    if not (rel_path.startswith("docs/prd/") or rel_path.startswith("docs/epics/")):
        return []
    if os.path.basename(rel_path) == "_template.md":
        return []

    fenced_stripped = strip_fenced_code_blocks(text)
    partial = strip_html_comment_blocks(fenced_stripped)
    full = sanitize_status_text(text)

    if _STATUS_ANY_RE.search(partial) and not _STATUS_ANY_RE.search(full):
        return [
            LintError(
                path=rel_path,
                message=(
                    "ステータス行がインデント（4スペース以上）されています。"
                    "メタ情報のステータスはトップレベル（インデントなし）で記述してください。"
                    "例: - ステータス: Approved"
                ),
            )
        ]
    return []


def lint_research_contract(rel_path: str, text: str) -> List[LintError]:
    if not rel_path.startswith("docs/research/"):
        return []

    if not rel_path.endswith(".md"):
        return []

    base = os.path.basename(rel_path)

    if base == "README.md":
        return []

    is_template = rel_path in {
        "docs/research/prd/_template.md",
        "docs/research/epic/_template.md",
        "docs/research/estimation/_template.md",
    }
    is_date_artifact = re.match(r"^\d{4}-\d{2}-\d{2}\.md$", base) is not None

    if not is_template and not is_date_artifact:
        return [
            LintError(
                path=rel_path,
                message=(
                    "docs/research 配下の調査成果物は日付ファイル（YYYY-MM-DD.md）で保存してください。"
                    "補助ドキュメントは README.md を使用してください。"
                    "テンプレートは次の3つのみ許可します: "
                    "docs/research/prd/_template.md, docs/research/epic/_template.md, "
                    "docs/research/estimation/_template.md"
                ),
            )
        ]

    errs: List[LintError] = []

    contract_text = strip_html_comment_blocks(
        strip_inline_code_spans(
            strip_indented_code_blocks(strip_fenced_code_blocks(text))
        )
    )

    candidate_blocks = list(_RESEARCH_CANDIDATE_BLOCK_RE.finditer(contract_text))
    if len(candidate_blocks) < 5:
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "調査ドキュメントには候補（候補-1..）を 5件以上含めてください。 "
                    f"検出件数: {len(candidate_blocks)}"
                ),
            )
        )

    required_field_labels = _RESEARCH_CANDIDATE_REQUIRED_LABELS
    for m in candidate_blocks:
        n_raw = m.group(1)
        block = m.group(0)
        cand = f"候補-{n_raw}"
        for label in required_field_labels:
            if re.search(rf"^\s*{re.escape(label)}", block, re.MULTILINE) is None:
                errs.append(
                    LintError(
                        path=rel_path,
                        message=(
                            "調査ドキュメントの候補フォーマットが不完全です。 "
                            f"{cand} に '{label}' がありません"
                        ),
                    )
                )

        if not is_template:
            applicability_lines = re.findall(
                r"^\s*適用可否:[ \t]*[^\n]*$", block, re.MULTILINE
            )
            if len(applicability_lines) != 1:
                errs.append(
                    LintError(
                        path=rel_path,
                        message=(
                            "調査ドキュメントの候補フォーマットが不完全です。 "
                            f"{cand} の '適用可否:' は 1件のみ記載してください"
                        ),
                    )
                )
            elif _RESEARCH_APPLICABILITY_RE.search(block) is None:
                errs.append(
                    LintError(
                        path=rel_path,
                        message=(
                            "調査ドキュメントの候補フォーマットが不完全です。 "
                            f"{cand} の '適用可否:' は Yes / Partial / No のいずれかで記載してください"
                        ),
                    )
                )

        if re.search(
            r"^\s*根拠リンク:", block, re.MULTILINE
        ) is not None and not has_candidate_evidence_url(block):
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "調査ドキュメントの根拠リンクが不完全です。 "
                        f"{cand} の '根拠リンク:' 配下に URL（- https://...）がありません"
                    ),
                )
            )

    if "タイムボックス:" not in contract_text:
        errs.append(
            LintError(
                path=rel_path,
                message="調査ドキュメントには 'タイムボックス:' を含めてください",
            ),
        )
    if "打ち切り条件:" not in contract_text:
        errs.append(
            LintError(
                path=rel_path,
                message="調査ドキュメントには '打ち切り条件:' を含めてください",
            ),
        )

    novelty = extract_h2_section(contract_text, _RESEARCH_NOVELTY_H2_RE)
    if not novelty.strip():
        if not is_template:
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "調査ドキュメントには見出し '## 新規性判定（発火条件）'（番号は任意）を含めてください"
                    ),
                )
            )

    if (not is_template) and re.search(r":\s*Yes\s*/\s*No\s*$", novelty, re.MULTILINE):
        errs.append(
            LintError(
                path=rel_path,
                message=(
                    "新規性判定（発火条件）は 'Yes' または 'No' で埋めてください（'Yes / No' のまま残さないでください）"
                ),
            )
        )

    if (not is_template) and novelty.strip():
        for s in _RESEARCH_NOVELTY_REQUIRED_TRIGGER_SUBSTRINGS:
            if (
                re.search(
                    rf"^\s*-\s*.*{re.escape(s)}.*:\s*(Yes|No)\s*$",
                    novelty,
                    re.MULTILINE,
                )
                is None
            ):
                errs.append(
                    LintError(
                        path=rel_path,
                        message=(
                            "新規性判定（発火条件）に必須トリガがありません（'Yes' または 'No' で記載してください）: "
                            f"{s}"
                        ),
                    )
                )

    adjacent_section = extract_h2_section(contract_text, _RESEARCH_ADJACENT_H2_RE)
    has_adjacent_na = (
        re.search(r"^\s*隣接領域探索\s*:\s*N/A", adjacent_section, re.MULTILINE)
        is not None
    )
    adjacent_required = (
        is_research_adjacent_exploration_required(contract_text)
        if not is_template
        else False
    )

    if adjacent_required:
        if has_adjacent_na:
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "新規性判定の結果、隣接領域探索が必須ですが、'隣接領域探索: N/A（理由）' になっています"
                    ),
                )
            )

        adjacent = _unique_ints(_RESEARCH_ADJACENT_RE.finditer(adjacent_section))
        if len(adjacent) < 2:
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "調査ドキュメントには隣接領域（隣接領域-1..）を 2件以上含めるか、'隣接領域探索: N/A（理由）' と記載してください"
                    ),
                )
            )

        abstractions = _unique_ints(_RESEARCH_ABSTRACTION_RE.finditer(adjacent_section))
        if len(abstractions) > 3:
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "調査ドキュメントの抽象化（抽象化-1..）は 3件以下にしてください。 "
                        f"検出件数: {len(abstractions)}"
                    ),
                )
            )

        if "適用マッピング" not in adjacent_section:
            errs.append(
                LintError(
                    path=rel_path,
                    message="調査ドキュメントには '適用マッピング' を含めるか、隣接領域探索を N/A としてください",
                )
            )
    else:
        if not has_adjacent_na:
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "新規性が高くない場合は、'隣接領域探索: N/A（理由）' を隣接領域探索セクションに記載してください"
                    ),
                )
            )

    if (
        rel_path.startswith("docs/research/epic/")
        and (not is_template)
        and is_date_artifact
    ):
        errs.extend(lint_epic_external_service_comparison(rel_path, contract_text))

    return errs


def lint_placeholders(_repo: str, rel_path: str, text: str) -> List[LintError]:
    errs: List[LintError] = []
    if is_approved_prd_or_epic(rel_path, text):
        scrubbed = strip_inline_code_spans(strip_fenced_code_blocks(text))
        if "<!--" in scrubbed and not _ALLOW_HTML_COMMENTS_RE.search(scrubbed):
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "Approved doc contains HTML comments ('<!--'). Remove placeholders, set status Draft/Review, "
                        "or add allow marker: <!-- lint-sot: allow-html-comments -->"
                    ),
                )
            )
    return errs


def lint_sot_reference_contract(repo: str, rel_path: str, text: str) -> List[LintError]:
    if not rel_path.startswith("docs/epics/"):
        return []
    if not is_approved_prd_or_epic(rel_path, text):
        return []

    contract_text = sanitize_status_text(text)
    refs = list(_SOT_REFERENCE_PRD_LINE_RE.finditer(contract_text))

    if len(refs) == 0:
        return [
            LintError(
                path=rel_path,
                message="Approved Epic に '参照PRD:' フィールドがありません（例: - 参照PRD: `docs/prd/xxx.md`）",
            )
        ]
    if len(refs) > 1:
        return [
            LintError(
                path=rel_path,
                message="Approved Epic に '参照PRD:' が複数あります（一意に解決してください）",
            )
        ]

    m = refs[0]
    ref_path = (m.group(1) or m.group(2) or "").strip()
    if not ref_path:
        return [
            LintError(
                path=rel_path,
                message="Approved Epic の '参照PRD:' が空です（docs/prd/xxx.md を指定してください）",
            )
        ]

    # Normalize to prevent path traversal (e.g. docs/prd/../epics/foo.md)
    normalized = os.path.normpath(ref_path).replace("\\", "/")
    if not normalized.startswith("docs/prd/"):
        return [
            LintError(
                path=rel_path,
                message="Approved Epic の '参照PRD:' は docs/prd/ 配下を指す必要があります",
            )
        ]

    # Resolve real path to guard against symlinks pointing outside docs/prd/
    prd_root_abs = os.path.realpath(os.path.join(repo, "docs/prd"))
    ref_abs = os.path.realpath(os.path.join(repo, normalized))
    if os.path.commonpath(
        [ref_abs, prd_root_abs]
    ) != prd_root_abs or not os.path.isfile(ref_abs):
        return [
            LintError(
                path=rel_path,
                message=(
                    "Approved Epic の '参照PRD:' が指すファイルが見つかりません: "
                    f"{ref_path}"
                ),
            )
        ]
    return []


_MD_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
_MD_REF_DEF_RE = re.compile(r"^[ \t]{0,3}\[[^\]]+\]:\s*(\S+)", re.MULTILINE)


def strip_inline_code_spans(text: str) -> str:
    """Remove inline code spans for link/placeholder linting.

    Unlike ``md_sanitize._mask_inline_code_spans`` (which is
    CommonMark-compliant and handles backslash-escaped backticks),
    this function intentionally ignores escapes.  It is only used
    by ``parse_md_link_targets`` and ``lint_placeholders`` where
    the sole requirement is to exclude code-span content from link
    and placeholder detection — precise escaped-backtick handling
    is unnecessary for that purpose.
    """
    out: List[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch != "`":
            out.append(ch)
            i += 1
            continue

        j = i
        while j < n and text[j] == "`":
            j += 1
        delim = text[i:j]

        k = text.find(delim, j)
        if k == -1:
            out.append(delim)
            i = j
            continue

        i = k + len(delim)

    return "".join(out)


def parse_md_link_targets(text: str) -> List[str]:
    out: List[str] = []
    scrubbed = strip_inline_code_spans(strip_fenced_code_blocks(text))
    for m in _MD_LINK_RE.finditer(scrubbed):
        target = (m.group(1) or "").strip()
        if not target:
            continue
        out.append(target)
    for m in _MD_REF_DEF_RE.finditer(scrubbed):
        target = (m.group(1) or "").strip()
        if not target:
            continue
        out.append(target)
    return out


def is_external_or_fragment(target: str) -> bool:
    t = target.strip()
    if not t:
        return True
    if t.startswith("#"):
        return True
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", t):
        return True
    if t.startswith("mailto:"):
        return True
    return False


def normalize_target(target: str) -> str:
    t = target.strip()
    if t.startswith("<") and t.endswith(">"):
        t = t[1:-1].strip()
    if (t.startswith('"') and t.endswith('"')) or (
        t.startswith("'") and t.endswith("'")
    ):
        t = t[1:-1].strip()
    if " " in t or "\t" in t or "\n" in t:
        t = t.split()[0]
    t = t.split("#", 1)[0].split("?", 1)[0].strip()
    return t


def resolve_to_repo_relative(repo: str, file_abs: str, target: str) -> Optional[str]:
    t = normalize_target(target)
    if not t:
        return None

    if t.startswith("/"):
        abs_candidate = os.path.realpath(os.path.join(repo, t[1:]))
    else:
        file_dir = os.path.dirname(file_abs)
        abs_candidate = os.path.realpath(os.path.join(file_dir, t))
    repo_abs = os.path.realpath(repo)
    if not abs_candidate.startswith(repo_abs + os.sep) and abs_candidate != repo_abs:
        return None

    rel = os.path.relpath(abs_candidate, repo_abs).replace(os.sep, "/")
    return rel


def lint_relative_links(repo: str, rel_path: str, text: str) -> List[LintError]:
    errs: List[LintError] = []

    file_abs = os.path.join(repo, rel_path)
    for raw in parse_md_link_targets(text):
        if is_external_or_fragment(raw):
            continue
        rel = resolve_to_repo_relative(repo, file_abs, raw)
        if not rel:
            errs.append(
                LintError(
                    path=rel_path,
                    message=f"Unsafe or out-of-repo relative link target: {raw}",
                )
            )
            continue
        if not os.path.exists(os.path.join(repo, rel)):
            errs.append(
                LintError(
                    path=rel_path,
                    message=f"Broken relative link target (not found): {raw} -> {rel}",
                )
            )
    return errs


def lint_paths(repo: str, roots: List[str]) -> List[LintError]:
    errs: List[LintError] = []
    for root in roots:
        if not is_safe_repo_relative_root(root):
            errs.append(
                LintError(
                    path=str(root),
                    message="Root path must be repo-relative (no abs path, no '..')",
                )
            )
            continue
        root_abs = os.path.realpath(os.path.join(repo, root))
        repo_abs = os.path.realpath(repo)
        if not root_abs.startswith(repo_abs + os.sep) and root_abs != repo_abs:
            errs.append(
                LintError(
                    path=str(root),
                    message="Root path resolves outside repo",
                )
            )
            continue
        if not os.path.exists(root_abs):
            errs.append(LintError(path=root, message="Path does not exist"))
            continue
        for path_abs in iter_markdown_files(root_abs):
            rel_path = os.path.relpath(path_abs, repo).replace(os.sep, "/")
            text = read_text(path_abs)
            errs.extend(lint_placeholders(repo, rel_path, text))
            errs.extend(lint_status_format(rel_path, text))
            errs.extend(lint_research_contract(rel_path, text))
            errs.extend(lint_sot_reference_contract(repo, rel_path, text))
            errs.extend(lint_relative_links(repo, rel_path, text))
    return errs


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Lint Agentic-SDD SoT/docs for determinism and link integrity"
    )
    ap.add_argument(
        "paths",
        nargs="*",
        default=["docs"],
        help="Root paths to lint (repo-relative). Default: docs",
    )
    args = ap.parse_args(argv)

    repo = repo_root()
    errs = lint_paths(repo, list(args.paths))
    if errs:
        eprint("[lint-sot] BLOCKED")
        for err in errs:
            eprint(f"- {err.path}: {err.message}")
        eprint("\nNext actions:")
        eprint(
            "- Remove placeholders in Approved PRD/Epic, or change status to Draft/Review"
        )
        eprint("- Fix broken relative links (or switch to an https:// URL)")
        return 1
    print("[lint-sot] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
