# 意思決定ログ（Decision Snapshot）

意思決定の本文は `docs/decisions/` 配下に「1決定 = 1ファイル」で保存します。
このファイルは索引（index）だけを担い、本文を直接持ちません。

---

## 運用ルール

- append-only: 既存のDecision本文ファイルは上書きしない
- supersede方式: 変更は新規Decisionファイルを追加し、`Supersedes` で置換関係を明示する
- 1決定 = 1ファイル: 1つのファイルに複数Decisionを混在させない
- 必須フォーマット: `Decision-ID / Context / Rationale / Alternatives / Impact / Verification / Supersedes / Inputs Fingerprint`
- index更新必須: `.agent/commands/final-review.md` の `Decision Necessity Checklist` が required の場合、`## Decision Index` に対象Decisionファイルを必ず追記する

詳細は `docs/decisions/README.md` と `docs/decisions/_template.md` を参照してください。

---

## Decision Index

- D-2026-02-18-RUFF_S_RULE_ROLLOUT: [`docs/decisions/d-2026-02-18-ruff-s-rule-rollout.md`](./decisions/d-2026-02-18-ruff-s-rule-rollout.md)
