# /impl

Issueの実装を開始するコマンド。Full見積もりを作成してから実装に着手する。

## 使用方法

```
/impl [Issue番号]
```

## 実行フロー

### Phase 1: Issue読み込み

1. 指定されたIssueを読み込み
2. 関連するEpic、PRDを特定
3. ACを抽出

### Phase 2: Full見積もり作成（必須）

**11セクションすべてを記載**。該当なしは「N/A（理由）」と明記。

```markdown
## Full見積もり

### 0. 前提確認

- Issue: #[番号] [タイトル]
- Epic: [Epicファイル]
- PRD: [PRDファイル]
- 技術方針: [シンプル優先/バランス/拡張性優先]

### 1. 依頼内容の解釈

[Issueの内容を自分の言葉で要約。誤解がないか確認]

### 2. 変更対象（ファイル:行）

Change-1
file: `src/xxx.ts`
change: [変更内容]
loc_range: 20-30行

Change-2
file: `src/yyy.ts`
change: [変更内容]
loc_range: 10-20行

total_loc_range: 50-100行

### 3. 作業項目と工数（レンジ + 信頼度）

Task-1
task: [作業1]
effort_range: 1-2h
confidence: High

Task-2
task: [作業2]
effort_range: 0.5-1h
confidence: Med

Task-3
task: [テスト作成]
effort_range: 1-2h
confidence: Med

total_effort_range: 2.5-5h
overall_confidence: High / Med / Low

### 4. DB影響

[DBスキーマ変更、マイグレーション、データ移行などを記載]

または

N/A（本IssueはDB変更なし。フロントエンドのみの変更）

### 5. ログ出力

[追加/変更するログ出力を記載]

または

N/A（ログ変更なし。既存のログ出力で十分）

### 6. I/O一覧

[外部API呼び出し、ファイル読み書き、外部サービス連携を記載]

IO-1
type: API
target: [エンドポイント]
purpose: [用途]

または

N/A（外部I/Oなし。内部処理のみ）

### 7. リファクタ候補

[実装時に気づいたリファクタリング候補を記載]

または

N/A（現時点でリファクタ候補なし。コードベースが新規のため）

### 8. フェーズ分割

[大きなIssueの場合、段階的な実装計画を記載]

または

N/A（単一フェーズで完了可能。推定行数100行以下）

### 9. テスト計画

AC をテスト TODO に分解し、`skills/tdd-protocol.md` のサイクル（Red → Green → Refactor）で 1 つずつ進める。

Test-1
kind: Unit
target: [対象]
content: [テスト内容]

Test-2
kind: Integration
target: [対象]
content: [テスト内容]

### 10. 矛盾点/不明点/確認事項

[PRD/Epic/Issueに矛盾や不明点があれば記載]

- [ ] [確認事項1]
- [ ] [確認事項2]

または

なし（PRD/Epic/Issueは整合している）

### 11. 変更しないこと

[スコープ外を明示。誤って変更しないように]

- [変更しないこと1]
- [変更しないこと2]
```

### Phase 3: 信頼度の判定

- High: 類似実績あり、影響範囲が明確（対応: レンジは狭くてOK）
- Med: 一部不確実だがレンジ内で収まる見込み（対応: レンジはやや広めに）
- Low: 不確実性が高い、Unknownが残っている（対応: レンジを2倍に広げる or 確認質問を出す）

### Phase 4: 確認事項の解消

セクション10に確認事項がある場合：
1. ユーザーに質問
2. 回答を待つ
3. 見積もりを更新

### Phase 5: 実装開始の確認

```
見積もりが完成しました。

- 合計推定行数: [50-100行]
- 合計工数: [2.5-5h]
- 全体信頼度: [Med]
- 確認事項: [なし / あり（要回答）]

実装を開始してよろしいですか？
```

### Phase 6: 実装

1. ブランチを作成（`.agent/rules/branch.md` 参照）
2. 見積もりに沿って実装
3. テストを作成
4. コミット（`.agent/rules/commit.md` 参照）

### Phase 7: 実装完了

```
実装が完了しました。

- 実際の行数: [75行]（見積もり: 50-100行 → 範囲内）
- 実際の工数: [3h]（見積もり: 2.5-5h → 範囲内）

次のステップ:
1. （任意）/review-cycle でローカルレビューを回す
2. /review を実行して最終セルフレビュー
3. PRを作成
```

## 見積もりのN/A記載ルール

- 4. DB影響: N/A（本Issueはフロントエンドのみ、DB操作なし）
- 5. ログ出力: N/A（ログ変更なし。既存のエラーログで十分）
- 6. I/O一覧: N/A（外部I/Oなし。内部計算処理のみ）
- 7. リファクタ候補: N/A（新規コードのため候補なし）
- 8. フェーズ分割: N/A（単一フェーズ。推定50行以下）

## オプション

- `--estimate-only`: 見積もりのみ作成（実装は開始しない）
- `--skip-confirm`: 実装開始の確認をスキップ

## 関連ファイル

- `skills/estimation.md` - 見積もりスキル詳細
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/issue.md` - Issue粒度規約

## 次のコマンド

実装完了後は `/review` を実行する。
