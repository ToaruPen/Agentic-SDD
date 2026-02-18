# SoT Index (Map-not-manual)

このディレクトリは「本文の正本」を増やす場所ではなく、Agentic-SDD リポジトリの SoT（System of Record）を辿るための索引（地図）です。

---

## SoT の優先順位

1. PRD（要件）
2. Epic（実装計画）
3. 実装（コード）

注意: 2つ以上のSoTが矛盾している場合は、実装では解決せず、参照元（PRD/Epic）を更新してから進めます。

---

## どこに何があるか

### 仕様・計画

- PRDテンプレ: [`docs/prd/_template.md`](../prd/_template.md)
- Epicテンプレ: [`docs/epics/_template.md`](../epics/_template.md)
- /research テンプレ:
  - PRD調査: [`docs/research/prd/_template.md`](../research/prd/_template.md)
  - Epic調査: [`docs/research/epic/_template.md`](../research/epic/_template.md)
  - 見積もり前調査: [`docs/research/estimation/_template.md`](../research/estimation/_template.md)

### 評価（quality gates）

- quality gates 一覧（必須）: [`docs/evaluation/quality-gates.md`](../evaluation/quality-gates.md)
- quality score（任意）: [`docs/evaluation/quality-score.md`](../evaluation/quality-score.md)

### 実行計画 / 進捗・判断ログ

- exec-plans（任意）: [`docs/exec-plans/index.md`](../exec-plans/index.md)

### ワークフロー（コマンド/ルール）

- コマンド定義: [`.agent/commands/`](../../.agent/commands/)
- ルール定義: [`.agent/rules/`](../../.agent/rules/)

### 意思決定 / 用語

- 意思決定ログ（index）: [`docs/decisions.md`](../decisions.md)
- 意思決定本文の運用: [`docs/decisions/README.md`](../decisions/README.md)
- 意思決定テンプレート: [`docs/decisions/_template.md`](../decisions/_template.md)
- 用語集: [`docs/glossary.md`](../glossary.md)

### メモ（背景/検討）

- Harness engineering 検討メモ: [`docs/memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md`](../memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md)

---

## この索引の運用ルール

- この索引は「参照先の一覧」と「参照順序」を提供する。詳細仕様の本文はここに書かない
- 新しい必須ドキュメントや必須ゲートを追加したら、必ずこの索引と `docs/evaluation/quality-gates.md` の両方を更新する
