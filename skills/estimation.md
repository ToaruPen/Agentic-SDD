# 見積もりスキル（Estimation）

実装前の見積もりを作成するためのスキル定義。

---

## 基本原則

```
1. 見積もりは"レンジ"で出す（例: 2〜4h / 50〜100行）
2. レンジの根拠を"観測事実"に紐づける
3. 不確実な点は Unknown として明示し、質問を出す
4. Unknown が解消されるまで見積もりは暫定扱い
5. 信頼度を必ず付与する
```

---

## Full見積もり（11セクション）

本プロジェクトでは **Full必須**。Liteモードは使用しない。

### 0. 前提確認

```markdown
- Issue: #[番号] [タイトル]
- Epic: [Epicファイルへのパス]
- PRD: [PRDファイルへのパス]
- 技術方針: [シンプル優先/バランス/拡張性優先]
```

**目的**: 見積もり対象を明確にし、参照先を記録する。

### 1. 依頼内容の解釈

```markdown
[Issueの内容を自分の言葉で要約]

- 主な目的: [何を達成するか]
- 対象ユーザー: [誰が使うか]
- 期待される結果: [どうなればOKか]
```

**目的**: 誤解がないか確認。ユーザーと認識を合わせる。

### 2. 変更対象（ファイル:行）

```markdown
Change-1
file: `src/api/users.ts`
change: ユーザー取得API追加
loc_range: 30-50行

Change-2
file: `src/models/user.ts`
change: Userモデル定義
loc_range: 20-30行

Change-3
file: `tests/api/users.test.ts`
change: テスト追加
loc_range: 50-80行

total_loc_range: 100-160行
```

**目的**: 影響範囲を特定し、行数を見積もる。

### 3. 作業項目と工数（レンジ + 信頼度）

```markdown
Task-1
task: Userモデル作成
effort_range: 0.5-1h
confidence: High
reason: 類似モデル実績あり

Task-2
task: API実装
effort_range: 1-2h
confidence: Med
reason: 認証周りに不確実性

Task-3
task: テスト作成
effort_range: 1-2h
confidence: Med
reason: カバレッジ要件未確認

Task-4
task: ドキュメント更新
effort_range: 0.5h
confidence: High
reason: 定型作業

total_effort_range: 3-5.5h
overall_confidence: Med
```

**目的**: 作業を分解し、それぞれに工数と信頼度を付与。

### 4. DB影響

```markdown
### スキーマ変更
- テーブル追加: `users`
- カラム: id, email, name, created_at, updated_at

### マイグレーション
- `migrations/001_create_users.sql`

### データ移行
- なし（新規テーブル）
```

または

```markdown
N/A（本IssueはDB変更なし。フロントエンドのみの変更）
```

**目的**: DB変更の影響を把握し、マイグレーション計画を立てる。

### 5. ログ出力

```markdown
### 追加するログ

Log-1
level: INFO
where: ユーザー作成成功時
message: `User created: {userId}`

Log-2
level: ERROR
where: 作成失敗時
message: `Failed to create user: {error}`

### 変更するログ
- なし
```

または

```markdown
N/A（ログ変更なし。既存のログ出力で十分）
```

**目的**: 運用時のトラブルシューティングに必要なログを計画。

### 6. I/O一覧

```markdown
IO-1
type: API
target: POST /api/users
purpose: ユーザー作成
on_error: 400/500エラー返却

IO-2
type: DB
target: users テーブル
purpose: CRUD操作
on_error: トランザクションロールバック
```

または

```markdown
N/A（外部I/Oなし。内部計算処理のみ）
```

**目的**: 外部依存を把握し、エラーハンドリングを計画。

### 7. リファクタ候補

```markdown
### 発見したリファクタ候補
1. `src/utils/validation.ts` - バリデーション関数の共通化
   - 現状: 各ファイルで重複実装
   - 提案: 共通モジュールに抽出
   - 影響: 本Issueでは対応しない（別Issueで対応）

2. なし
```

または

```markdown
N/A（現時点でリファクタ候補なし。コードベースが新規のため）
```

**目的**: 技術的負債を発見し、記録する。

### 8. フェーズ分割

```markdown
### Phase 1: 基本実装（Day 1）
- Userモデル作成
- 基本的なCRUD API

### Phase 2: 拡張（Day 2）
- バリデーション追加
- エラーハンドリング強化

### Phase 3: テスト（Day 3）
- ユニットテスト
- 統合テスト
```

または

```markdown
N/A（単一フェーズで完了可能。推定行数100行以下）
```

**目的**: 大きなIssueを段階的に進める計画を立てる。

### 9. テスト計画

```markdown
Test-1
kind: Unit
target: Userモデル
content: バリデーションロジック
priority: 高

Test-2
kind: Unit
target: API handler
content: リクエスト処理
priority: 高

Test-3
kind: Integration
target: POST /api/users
content: E2E作成フロー
priority: 中

Test-4
kind: Integration
target: GET /api/users
content: E2E取得フロー
priority: 中

### カバレッジ目標
- 新規コード: 80%以上
```

**目的**: テスト戦略を明確にする。

### 10. 矛盾点/不明点/確認事項

```markdown
### 矛盾点
- PRD AC-3「メール重複時はエラー」とEpic「重複時は上書き」が矛盾
  - 確認が必要

### 不明点
- [ ] パスワードのハッシュアルゴリズムは？（bcrypt推奨）
- [ ] メール認証フローは本Issueに含む？

### 確認事項
- [ ] 上記矛盾の解決方針を確認
```

または

```markdown
なし（PRD/Epic/Issueは整合している）
```

**目的**: 実装前に不明点を解消する。

### 11. 変更しないこと

```markdown
本Issueでは以下を変更しない：

- 認証フロー（別Issue #15 で対応）
- 管理者向け機能（スコープ外）
- パフォーマンス最適化（MVP後に検討）
```

**目的**: スコープクリープを防ぐ。

---

## 信頼度の定義

- High: 類似実績あり、影響範囲が明確（レンジ目安: ±20% / 対応: そのまま進める）
- Med: 一部不確実だがレンジ内で収まる見込み（レンジ目安: ±50% / 対応: レンジをやや広めに）
- Low: 不確実性が高い、Unknownが残っている（レンジ目安: ±100% / 対応: レンジを2倍に広げる or 確認質問）

### Low の場合の対応

1. **レンジを広げる**: 2〜4h → 2〜8h
2. **確認質問を出す**: Unknownを解消してから再見積もり

---

## レンジの根拠

見積もりのレンジは**観測事実**に紐づける：


- 類似変更の実績: 「前回の類似APIは3時間で完了」
- 影響範囲: 「変更ファイル3つ、依存関係なし」
- 既存テストの有無: 「既存テストあり、追加テスト少量」
- 技術的な確実性: 「使用経験のあるライブラリ」

**禁止**: 「なんとなく」「経験上」などの曖昧な根拠

---

## N/A記載ルール

該当しないセクションは「N/A」と明記し、**理由を括弧で添える**。


- 4. DB影響: N/A（本Issueはフロントエンドのみ、DB操作なし）
- 5. ログ出力: N/A（ログ変更なし。既存のエラーログで十分）
- 6. I/O一覧: N/A（外部I/Oなし。内部計算処理のみ）
- 7. リファクタ候補: N/A（新規コードのため候補なし）
- 8. フェーズ分割: N/A（単一フェーズ。推定50行以下）

---

## 見積もり後の運用

### 実績との比較

実装完了後、見積もりと実績を比較：

```markdown
- 行数: 見積もり=100-160行 / 実績=145行 / 差異=範囲内
- 工数: 見積もり=3-5.5h / 実績=4.5h / 差異=範囲内
```

### 差異が大きい場合

- 差異の原因を分析
- 次回の見積もり精度向上に活用
- 必要に応じて見積もり手法を改善

---

## 関連ファイル

- `.agent/commands/impl.md` - 実装コマンド
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/issue.md` - Issue粒度規約
