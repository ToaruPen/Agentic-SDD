# Observability Rules

観測性要件があるプロジェクト向けのルール。

適用条件: PRD Q6-6（監査ログ要件）で「Yes」と回答した場合

---

## Required when

<!-- grepキーワード: OBSERVABILITY_REQUIRED_WHEN -->

以下のいずれかに該当する場合、このルールを適用：

- [ ] 本番環境にデプロイされる
- [ ] 障害時の原因特定が必要
- [ ] 監査要件がある（金融、医療、政府系）
- [ ] 分散システム（マイクロサービス、非同期処理）
- [ ] SLO/SLAがある
- [ ] 複数人で運用する

---

## Not required when

<!-- grepキーワード: OBSERVABILITY_NOT_REQUIRED_WHEN -->

以下の場合は適用不要：

- 使い捨てスクリプト（一度きりの実行）
- ローカル専用ツール（個人利用）
- プロトタイプ/PoC（動作確認が目的）
- 運用しないコード（ライブラリ、SDK）

---

## PRD requirements

<!-- grepキーワード: OBSERVABILITY_PRD_REQ -->

PRD Q6-6で「Yes」の場合、以下を記載：

1. 監査要件の有無（誰が何をしたかの記録が必要か）
2. ログ保持期間の要件（規制等）

詳細な設計はEpicで定義する。

---

## Epic requirements

<!-- grepキーワード: OBSERVABILITY_EPIC_REQ -->

Epicに以下のセクションを必須で含める：

<epic_section name="観測性設計">

### 観測性設計（PRD Q6-6: Yesの場合必須）

ログ:
- 出力先: [例: stdout, ファイル, CloudWatch, Datadog]
- フォーマット: [例: JSON, 構造化ログ]
- レベル: [例: ERROR, WARN, INFO, DEBUG]
- 保持期間: [例: 30日、1年（監査要件）]

メトリクス:
- [メトリクス名]: [説明]
- 例: request_duration_seconds: リクエスト処理時間
- 例: request_count: リクエスト数
- 例: error_count: エラー発生数

トレース（分散システムの場合）:
- 方式: [例: OpenTelemetry, Jaeger, X-Ray]
- 伝播: [例: W3C Trace Context, B3]

アラート:
- [条件]: [通知先]
- 例: エラー率5%超過: Slack #alerts
- 例: レスポンス時間p99 > 5秒: PagerDuty

</epic_section>

---

## DoD requirements

<!-- grepキーワード: OBSERVABILITY_DOD_REQ -->

DoDで以下が必須化（Q6-6: Yesの場合）：

- [ ] ログ出力が実装されている
- [ ] エラー時に十分なコンテキストがログに含まれる
- [ ] 機密情報がログに含まれていない

---

## Log level guidelines

<!-- grepキーワード: OBSERVABILITY_LOG_LEVELS -->

| レベル | 用途 | 例 |
|-------|------|-----|
| ERROR | 即時対応が必要 | DB接続失敗、データ不整合 |
| WARN | 注意が必要 | リトライ発生、閾値接近 |
| INFO | 重要な正常イベント | リクエスト開始/終了、状態変更 |
| DEBUG | 開発時のみ | 詳細なデータ内容、中間状態 |

---

## Log content guidelines

<!-- grepキーワード: OBSERVABILITY_LOG_CONTENT -->

含めるべき情報:
- タイムスタンプ（ISO 8601）
- ログレベル
- リクエストID / トレースID
- ユーザーID（該当する場合）
- 操作内容
- 結果（成功/失敗）
- エラー時: スタックトレース

含めてはいけない情報:
- パスワード
- アクセストークン
- クレジットカード番号
- PII（マスクが必要）

---

## Checklist

<!-- grepキーワード: OBSERVABILITY_CHECKLIST -->

### 設計時

- [ ] ログ出力先が決定している
- [ ] ログフォーマットが決定している
- [ ] メトリクス項目が定義されている
- [ ] アラート条件が定義されている

### 実装時

- [ ] エラー時にスタックトレースが記録される
- [ ] リクエストIDなどのコンテキストが含まれる
- [ ] 機密情報がマスクされている
- [ ] ログレベルが適切に使い分けられている

### 運用時

- [ ] アラート条件が設定されている
- [ ] ログ検索が可能（クエリ可能な形式）
- [ ] ダッシュボードが用意されている

---

## Examples

<example type="good">
```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "request_id": "req-abc123",
  "user_id": "user-456",
  "action": "user.login",
  "result": "success",
  "duration_ms": 150
}
```
</example>

<example type="bad">
```
User logged in successfully
（タイムスタンプなし、コンテキストなし、構造化されていない）
```
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/security.md` - Secret masking
- `skills/error-handling.md` - Error handling (logging)
- `docs/prd/_template.md` - PRD Q6-6
