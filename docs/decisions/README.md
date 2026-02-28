# Decision Snapshot 運用ルール

このディレクトリは、意思決定の本文を長期再現可能な形で保持するための置き場です。

---

## 基本方針

- 1決定 = 1ファイル（append-only）
- 同じDecisionの更新は上書き禁止。必ず新しいDecision-IDで新規ファイルを作成
- 旧Decisionとの関係は `Supersedes` で明示する

---

## 命名規約

- ファイル名: `d-YYYY-MM-DD-short-kebab.md`
- Decision-ID: `D-YYYY-MM-DD-SHORT_KEBAB`

例:

- `d-2026-02-18-ruff-s-rule-rollout.md`
- `D-2026-02-18-RUFF_S_RULE_ROLLOUT`

---

## 必須項目

全Decision本文は次の項目を必須とします。

- Decision-ID
- Context
- Rationale
- Alternatives
- Impact
- Verification
- Supersedes
- Inputs Fingerprint

テンプレート: `docs/decisions/_template.md`

---

## Supersede手順

1. 既存ファイルは編集しない
2. 新しいDecisionファイルを作成する
3. 新ファイルの `Supersedes` に旧Decision-IDを記載する
4. `docs/decisions.md` の Index に新規Decisionを追記する

---

## 検証ゲート

- `/create-pr` 前に `python3 scripts/validate-decision-index.py` が必須ゲートとして実行される（`scripts/create-pr.sh` に組み込み済み）

---

## 非目標

- このPhaseでは `decision-snapshot` 自動生成は行わない

---

## exec-plans の判断ログとの関係

exec-plans（[`docs/exec-plans/`](../exec-plans/index.md)）の判断ログと、このディレクトリの Decision 本文は役割が異なります。

| | exec-plans 判断ログ | Decision 本文（このディレクトリ） |
|-|---|---|
| 目的 | Issue内の判断を追記する（軽量・インライン） | 将来の参照に耐える正式記録（長期保存） |
| 形式 | 1行プレーンテキスト | 構造化テンプレート（Context/Rationale/Alternatives/Impact…） |
| 粒度 | 判断の要点だけ | 背景・代替案・検証を含む詳細 |
| 寿命 | Issue完了まで | 無期限（Supersedeされるまで有効） |

**昇格のタイミング:**

判断ログのエントリが次のいずれかに該当する場合は、Decision 本文を作成して判断ログからリンクする:

- 他のIssueや将来の実装に影響する（アーキテクチャ・技術選定・廃止方針など）
- 「なぜそうしたか」を数ヶ月後に再現できる必要がある
- 代替案を比較した上で選択した（詳細を残す価値がある）

判断ログだけで十分な場合（昇格不要）:

- Issue内で完結する判断（他に影響しない）
- 実装の詳細は違うが方針は変わらない判断
