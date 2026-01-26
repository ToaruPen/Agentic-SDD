# Availability Rules

可用性要件があるプロジェクト向けのルール。

適用条件: PRD Q6-8（可用性要件）で「Yes」と回答した場合

---

## Required when

<!-- grepキーワード: AVAILABILITY_REQUIRED_WHEN -->

以下のいずれかに該当する場合、このルールを適用：

- [ ] 24/7稼働が求められる
- [ ] ダウンがビジネス損失に直結する
- [ ] SLA/SLOがある（例: 99.9%稼働）
- [ ] 障害復旧計画が必要
- [ ] 外部顧客にサービス提供する
- [ ] 決済/予約など中断不可の処理がある

---

## Not required when

<!-- grepキーワード: AVAILABILITY_NOT_REQUIRED_WHEN -->

以下の場合は適用不要：

- 内部ツール（業務時間のみ利用）
- プロトタイプ/PoC（動作確認が目的）
- 個人利用のみ
- ダウンしても影響が軽微

---

## PRD requirements

<!-- grepキーワード: AVAILABILITY_PRD_REQ -->

PRD Q6-8で「Yes」の場合、以下を記載：

1. 稼働要件の概要（例: 24/7、業務時間のみ）
2. SLA/SLOの有無

詳細な設計・復旧計画はEpicで定義する。

---

## Epic requirements

<!-- grepキーワード: AVAILABILITY_EPIC_REQ -->

Epicに以下のセクションを必須で含める：

<epic_section name="可用性設計">

### 可用性設計（PRD Q6-8: Yesの場合必須）

SLO:
- 稼働率: [例: 99.9%（月間ダウンタイム43分以内）]
- 許容ダウンタイム: [例: 月間43分]
- 応答時間: [例: p99 < 3秒]

冗長化:
- 方式: [例: マルチAZ、レプリカ、ロードバランサー]
- フェイルオーバー: [自動/手動]

障害復旧:
- RTO（復旧目標時間）: [例: 1時間]
- RPO（復旧目標地点）: [例: 直前バックアップ、最大1時間のデータ損失許容]
- バックアップ頻度: [例: 日次、1時間ごと]
- バックアップ保持期間: [例: 30日]

ロールバック:
- 方式: [例: Blue-Green, Canary, 手動切り戻し]
- 手順: [概要]
- 所要時間: [例: 5分以内]

</epic_section>

---

## DoD requirements

<!-- grepキーワード: AVAILABILITY_DOD_REQ -->

DoDで以下が必須化（Q6-8: Yesの場合）：

- [ ] ロールバック手順が文書化されている
- [ ] バックアップが設定されている
- [ ] 障害時の連絡先/手順が明確

---

## SLO guidelines

<!-- grepキーワード: AVAILABILITY_SLO -->

| 稼働率 | 月間ダウンタイム | 用途例 |
|-------|----------------|--------|
| 99% | 7時間18分 | 内部ツール、非クリティカル |
| 99.9% | 43分 | 一般的なWebサービス |
| 99.95% | 22分 | ECサイト、SaaS |
| 99.99% | 4分 | 金融、決済、インフラ |

---

## Checklist

<!-- grepキーワード: AVAILABILITY_CHECKLIST -->

### 設計時

- [ ] SLOが数値で定義されている
- [ ] 冗長化方式が決定している
- [ ] RTO/RPOが定義されている
- [ ] バックアップ方式が決定している

### 実装時

- [ ] ヘルスチェックエンドポイントがある
- [ ] Graceful shutdownが実装されている
- [ ] タイムアウト/リトライが適切に設定されている
- [ ] 外部依存の障害時にもサービスが安定する

### 運用時

- [ ] バックアップが定期実行されている
- [ ] バックアップのリストアがテストされている
- [ ] ロールバック手順がテストされている
- [ ] インシデント対応手順がある
- [ ] オンコール体制がある（24/7の場合）

---

## Examples

<example type="good">
SLO:
- 稼働率: 99.9%（月間ダウンタイム43分以内）
- p99レスポンス: 3秒以内

障害復旧:
- RTO: 1時間
- RPO: 1時間（1時間ごとのバックアップ）
- バックアップ: RDS自動バックアップ + S3クロスリージョンレプリケーション

ロールバック:
- 方式: Blue-Greenデプロイ
- 手順: AWS CodeDeployでトラフィック切り替え
- 所要時間: 5分以内
</example>

<example type="bad">
可用性: 高くする
（数値なし、具体的な方式なし、復旧計画なし）
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/observability.md` - Monitoring for availability
- `.agent/rules/performance.md` - Response time SLO
- `docs/prd/_template.md` - PRD Q6-8
