# Quality Score（品質の健康診断）

このドキュメントは Agentic-SDD の「品質の健康診断」を、時系列で追跡するためのテンプレです。

重要:

- これは **Gate（合否判定）ではない**。合否判定は [`docs/evaluation/quality-gates.md`](quality-gates.md) が担う
- スコアは「投資判断」「改善の優先順位付け」「GCの回収方針」のために使う
- SoTの優先順位・参照ルールは [`docs/sot/README.md`](../sot/README.md) を参照

---

## 更新頻度 / 更新者

- 推奨頻度: 週1（またはリリース毎）
- 更新者（想定）:
  - Human: 主担当（手動で更新）
  - GC: 定期回収（lint/link等の結果から一部を自動反映）
  - External harness: 外部のオーケストレーション層が集計して貼る（任意）

---

## 評価の軸（例）

各軸は 0-3 で評価し、根拠（Evidence）を1つ以上添える。

- 0: なし / 追跡不能
- 1: 部分的 / たまに
- 2: ある程度 / 継続
- 3: 十分 / 仕組み化

### 軸A: テスト（回帰/信頼性）

- 観点: 重要ロジックの回帰防止、失敗の再現性、テストの証跡
- Evidence例: `tests.txt`、CIログ、`/review-cycle` の `Tests:`

### 軸B: 仕様の一貫性（SoT: PRD/Epic/実装）

- 観点: PRD/Epic/実装が矛盾なく追跡できるか、入力が決定的か
- Evidence例: `/sync-docs` の結果、SoT参照の一意性

### 軸C: 型/静的解析（ある場合）

- 観点: typecheck の運用、危険な回避（`as any` 等）の抑止
- Evidence例: typecheck コマンド、CIログ

### 軸D: 観測（ログ/エラー/監査）

- 観点: 失敗時に原因特定できるか、エラー分類があるか
- Evidence例: `.agent/rules/observability.md`、アプリログ設計

### 軸E: セキュリティ

- 観点: 認証/認可/秘密情報、依存の脆弱性、危険なパターンの抑止
- Evidence例: `.agent/rules/security.md`、依存監査

### 軸F: パフォーマンス/可用性（必要な場合）

- 観点: SLO/性能要件がある場合に、測定と改善が回っているか
- Evidence例: `.agent/rules/performance.md`、計測結果

### 軸G: ドキュメント健全性

- 観点: リンク切れ/プレースホルダ、テンプレからの未更新
- Evidence例: `scripts/agentic-sdd/lint-sot.py`、定期GC

---

## Gate 連動メトリクス（定点観測）

このセクションは、[`quality-gates.md`](quality-gates.md) の Gate 合否（二値）と、上記の品質スコア（0-3 グラデーション）を橋渡しするための定点観測テンプレです。

重要な区別:

- **Gate（合否）**: 必須チェックポイント。Pass でなければ次工程に進めない。定義は [`quality-gates.md`](quality-gates.md) が持つ
- **Gate 連動メトリクス（このセクション）**: 健康シグナル。Gate の通過状況を時系列で観測し、投資判断・改善優先度の参考にする。合否の代替ではない

### YYYY-MM-DD

各 Gate の Pass/Fail と根拠リンクを記録する。更新頻度は品質スコアと同じ（週1またはリリース毎）。
日付見出しごとにテーブルを追記する（append-only。スコア記録と同じ運用）。

| Gate名 | Pass/Fail | 根拠リンク | 備考 |
| --- | --- | --- | --- |
| Gate 0: Worktree preconditions are satisfied |  |  |  |
| Gate 1: SoT resolution is deterministic |  |  |  |
| Gate 2: Change evidence (diff) is unambiguous |  |  |  |
| Gate 3: Quality checks (tests/lint/typecheck) are executed with evidence |  |  |  |
| Gate 4: Local iterative review (`review.json`) is schema-compliant |  |  |  |
| Gate 5: Final review (DoD + docs sync) passes |  |  |  |

根拠リンク例: CIログURL、`review.json` のパス、`/review-cycle` 出力のスニペット

### 計測タイミングと判定基準

- **計測タイミング**: 品質スコア更新と同じタイミング（週1またはリリース毎）で記録する
- **判定基準**: 各 Gate の Pass/Fail 定義は [`quality-gates.md`](quality-gates.md) を参照。このセクションでは基準を再定義しない

---

## スコア記録（時系列）

以下を追記（append-only）する。

### YYYY-MM-DD

| Axis | Score | Evidence | Note |
| --- | ---: | --- | --- |
| A: テスト |  |  |  |
| B: SoT |  |  |  |
| C: 型 |  |  |  |
| D: 観測 |  |  |  |
| E: セキュリティ |  |  |  |
| F: 性能/可用性 |  |  |  |
| G: ドキュメント |  |  |  |

補足:

- Gateに使わない（合否の代わりにしない）。合否判定は [`quality-gates.md`](quality-gates.md) の責務である
- スコアが下がったら「なぜ」を書く（GC/大規模変更/負債の顕在化など）
