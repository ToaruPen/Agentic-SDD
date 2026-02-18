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

## 非目標

- このPhaseでは `decision-snapshot` 自動生成は行わない
- 必須化ゲートの強制実装は行わない（確認観点の追加まで）
