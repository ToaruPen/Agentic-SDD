# /review

Review a PR or an Issue.

User-facing output remains in Japanese.

## Usage

```
/review [PR-number | Issue-number]
```

If omitted, review the PR associated with the current branch.

## Flow

### Phase 1: Identify the target

1. Identify the PR number or Issue number
2. Identify related PRD and Epic
3. Collect the list of changed files

### Phase 2: Run `/sync-docs` (required)

Run `/sync-docs` before reviewing.

```markdown
## 同期結果

### 差分の種類
- [ ] 仕様変更
- [ ] 解釈変更
- [ ] 実装都合

### 推奨アクション
- [ ] PRD更新が必要
- [ ] Epic更新が必要
- [ ] 実装修正が必要
- [ ] 差分なし（同期済み）

### 参照（必須）
- PRD: [ファイル名] セクション [番号/名前]
- Epic: [ファイル名] セクション [番号/名前]
- 該当コード: [ファイル:行]
```

### Phase 3: DoD check

Issue completion (required):

```
[] All AC are satisfied
[] Tests are added/updated (when applicable)
[] /sync-docs is "no diff" or diff is approved
[] Code review is complete
[] CI passes (when applicable)
```

PR completion (required):

- AC: all Issue AC satisfied
- sync-docs: no diff or diff is approved
- Tests: new/changed code is covered
- Review: at least one approval exists

### Phase 4: Verify AC

Verify each AC one-by-one.

```markdown
## AC検証結果

### AC1: [AC内容]
- 状態: 達成 / 未達成 / 部分的
- 確認方法: [どう確認したか]
- 証跡: [スクリーンショット / ログ / テスト結果]

### AC2: [AC内容]
- 状態: 達成 / 未達成 / 部分的
- 確認方法: [どう確認したか]
- 証跡: [スクリーンショット / ログ / テスト結果]
```

### Phase 5: Review focus areas

- Correctness: does it satisfy AC / PRD / Epic?
- Readability: names, structure, consistency
- Testing: meaningful assertions, enough coverage
- Security: input validation, auth, secret handling
- Performance: obvious issues

### Phase 6: Compare against the estimate

Compare actuals vs estimate.

```markdown
## 見積もり比較

- 行数: 見積もり=[50-100行] / 実績=[75行] / 差異=範囲内
- ファイル数: 見積もり=[3] / 実績=[3] / 差異=一致
- 工数: 見積もり=[2-4h] / 実績=[3h] / 差異=範囲内

### 差異の理由（大きい場合）
[差異が大きい場合は理由を記載]
```

### Phase 7: Output the review result

```markdown
## レビュー結果

### 総合判定
Approve / Request Changes / Comment

### sync-docs結果
差分なし / 差分あり（承認済み） / 差分あり（要対応）

### DoD達成状況
- [x] すべてのACが満たされている
- [x] テストが追加/更新されている
- [x] /sync-docs で差分なし
- [ ] コードレビューが完了している
- [x] CIが通っている

### AC検証結果
- AC1: 達成
- AC2: 達成
- AC3: 達成

### 指摘事項
1. [指摘内容]（重要度: 高/中/低）
2. [指摘内容]（重要度: 高/中/低）

### コメント
[総評やアドバイス]
```

## How to handle sync-docs results

- No diff: ready to merge
- Diff (minor): record the diff and proceed
- Diff (major): update PRD/Epic before merging

## Options

- `--quick`: only sync-docs + AC verification
- `--full`: full review across all focus areas
- `--ac-only`: only AC verification

## Related

- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/commands/sync-docs.md` - sync-docs command

## Next steps

- Approve: can merge
- Request Changes: fix and re-run `/review`
