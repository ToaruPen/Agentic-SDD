# Performance Rules

パフォーマンス要件があるプロジェクト向けのルール。

適用条件: PRD Q6-7（パフォーマンス要件）で「Yes」と回答した場合

---

## Required when

<!-- grepキーワード: PERFORMANCE_REQUIRED_WHEN -->

以下のいずれかに該当する場合、このルールを適用：

- [ ] ユーザーがインタラクティブに待つ操作がある（検索、一覧表示、フォーム送信等）
- [ ] 同時利用者が10人以上想定される
- [ ] 処理データ量が1000件以上/日
- [ ] SLA/契約で応答時間が定められている
- [ ] リソース制約がある（モバイル、組み込み、エッジデバイス）
- [ ] 競合と比較される（遅いと選ばれない）

---

## Not required when

<!-- grepキーワード: PERFORMANCE_NOT_REQUIRED_WHEN -->

以下の場合は適用不要：

- 内部ツール（少人数利用、待てる）
- 低頻度操作（年に数回）
- プロトタイプ/PoC（動作確認が目的）
- バッチ処理（時間制約が緩い、夜間に終われば良い）

---

## PRD requirements

<!-- grepキーワード: PERFORMANCE_PRD_REQ -->

PRD Q6-7で「Yes」の場合、以下を記載：

1. 対象操作の概要（例: 検索、一覧表示）
2. 大まかな目標（例: 「検索は数秒以内」）

詳細な目標値・測定方法はEpicで定義する。

---

## Epic requirements

<!-- grepキーワード: PERFORMANCE_EPIC_REQ -->

Epicに以下のセクションを必須で含める：

<epic_section name="パフォーマンス設計">

### パフォーマンス設計（PRD Q6-7: Yesの場合必須）

対象操作:
- [操作名]: [目標値]
- 例: 検索: 応答3秒以内
- 例: 一覧表示: 初回表示2秒以内

測定方法:
- ツール: [例: k6, Artillery, Lighthouse, ブラウザDevTools]
- 環境: [例: ステージング環境、本番相当データ量]
- 条件: [例: 同時100ユーザー、1000件データ]

ボトルネック候補:
- [候補]: [理由]
- 例: DBクエリ: N+1の可能性
- 例: 外部API: レスポンス時間が不明

対策方針:
- [対策]: [概要]
- 例: インデックス追加、キャッシュ導入、非同期化

</epic_section>

---

## DoD requirements

<!-- grepキーワード: PERFORMANCE_DOD_REQ -->

DoDで以下が必須化（Q6-7: Yesの場合）：

- [ ] パフォーマンス目標値を満たしている
- [ ] Before/After計測が記録されている
- [ ] 測定方法が明記されている

---

## Evidence format

<!-- grepキーワード: PERFORMANCE_EVIDENCE -->

パフォーマンス改善の報告には以下を含める：

```
Before: [数値] ([測定方法])
After: [数値] ([測定方法])
Target: [目標値]
Result: 達成 / 未達成（理由）
```

<example type="good">
Before: 検索応答 8.2秒（k6, 100同時ユーザー, ステージング）
After: 検索応答 1.8秒（同条件）
Target: 3秒以内
Result: 達成
</example>

<example type="bad">
パフォーマンスが改善されました。
（数値なし、測定方法なし、比較なし）
</example>

---

## Checklist

<!-- grepキーワード: PERFORMANCE_CHECKLIST -->

### 設計時

- [ ] 目標値がEpicに数値で定義されている
- [ ] 測定方法が決まっている
- [ ] 測定環境が明確（ステージング/本番相当）
- [ ] ボトルネック候補が特定されている

### 実装時

- [ ] Before計測が記録されている
- [ ] After計測が記録されている
- [ ] 目標値を満たしている（または理由が説明されている）

### レビュー時

- [ ] Before/After数値がエビデンスとして提示されている
- [ ] 測定条件が再現可能

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `skills/testing.md` - Test strategy
- `docs/prd/_template.md` - PRD Q6-7
