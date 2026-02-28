# SoT Index (Map-not-manual)

このディレクトリは「本文の正本」を増やす場所ではなく、Agentic-SDD リポジトリの SoT（System of Record）を辿るための索引（地図）です。

---

## SoT の優先順位

1. PRD（要件）
2. Epic（実装計画）
3. 実装（コード）

注意: 2つ以上のSoTが矛盾している場合は、実装では解決せず、参照元（PRD/Epic）を更新してから進めます。

### 参照ルール

- 参照は上位から下位へ辿る（PRD → Epic → 実装）。逆方向の参照（実装 → PRD）は「出典」としてのみ許容する
- 参照先が一意に解決できない場合（複数PRDが該当する等）は、作業を止めて人間に確認する
- 参照元が空、またはプレースホルダのままの場合は、入力不備として扱い実装に進まない
- 参照の有効性は [`docs/evaluation/quality-gates.md`](../evaluation/quality-gates.md) の Gate 1 で検証される。SoT参照契約違反（Approved Epic の `参照PRD:` 充足・一意性・実在性）は `scripts/lint-sot.py` で自動検証される

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
  - Note: quality-score.md includes a Gate-linked metrics (periodic observation) section. It tracks Gate pass/fail status over time as a health signal; Gate definitions themselves are owned by [`quality-gates.md`](../evaluation/quality-gates.md)

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

---

## 責務境界: 索引/契約と要求本文

この索引（`docs/sot/README.md`）と評価定義（`docs/evaluation/`）は **契約層** に属する。要求本文（PRD/Epic）とは責務が異なる。

| 層 | 責務 | 例 |
| --- | --- | --- |
| 索引/契約 | 参照先の列挙、参照順序、合否判定基準の定義 | `docs/sot/README.md`, `docs/evaluation/quality-gates.md` |
| 要求本文 | 要件・仕様・計画と受け入れ条件（AC）の記述（Gateの合否判定基準は持たない） | `docs/prd/*.md`, `docs/epics/*.md` |

原則:

- 索引/契約は「何をどこで辿るか」「何が Pass/Fail か」を定義する。要求の中身は書かない
- 要求本文は「何を作るか」「なぜ作るか」に加えて観測可能な受け入れ条件（AC）を記述する。Gateの合否判定基準は持たない
- ACは Issue / Review の検証可能性（トレーサビリティ）の根拠として扱う
- 両者の間に矛盾がある場合は、実装側で解決せず作業を停止し、参照元（PRD/Epic）を更新して解消する
