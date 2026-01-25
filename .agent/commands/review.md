# /review

Review a PR or an Issue.

This command is the SoT for review taxonomy (status/priority) shared by:

- `/review` (human-readable Japanese review output)
- `/review-cycle` (machine-readable `review.json` output)

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

### Phase 3: Review taxonomy (required)

#### Priorities (P0-P3)

- P0: must-fix (correctness/security/data-loss)
- P1: should-fix (likely bug / broken tests / risky behavior)
- P2: improvement (maintainability/perf minor)
- P3: nit (small clarity)

#### Status (`review.json.status`)

- `Approved`: `findings=[]` and `questions=[]`
- `Approved with nits`: findings may exist but must not include `P0`/`P1`; `questions=[]`
- `Blocked`: must include at least one `P0`/`P1` finding
- `Question`: must include at least one question

Recommended status selection precedence:

1. If any `P0`/`P1` finding exists -> `Blocked`
2. Else if any question exists -> `Question`
3. Else if any finding exists -> `Approved with nits`
4. Else -> `Approved`

#### Scope rules

- Only flag issues introduced by this diff (do not flag pre-existing issues).
- Be concrete; avoid speculation; explain impact.
- Ignore trivial style unless it obscures meaning or violates documented standards.
- For each finding, include evidence (`file:line`).

#### `review.json` shape (schema v3; used by `/review-cycle`)

- Required keys: `schema_version`, `scope_id`, `status`, `findings`, `questions`, `overall_explanation`
- Finding keys:
  - `title`: short title
  - `body`: 1 short paragraph (Markdown allowed)
  - `priority`: `P0|P1|P2|P3`
  - `code_location.repo_relative_path`: repo-relative path
  - `code_location.line_range`: `{start,end}` (keep as small as possible; overlap the diff)

### Phase 4: DoD check

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

### Phase 5: Verify AC

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

### Phase 6: Review focus areas

- Correctness: does it satisfy AC / PRD / Epic?
- Readability: names, structure, consistency
- Testing: meaningful assertions, enough coverage
- Security: input validation, auth, secret handling
- Performance: obvious issues

### Phase 7: Compare against the estimate

Compare actuals vs estimate.

```markdown
## 見積もり比較

- 行数: 見積もり=[50-100行] / 実績=[75行] / 差異=範囲内
- ファイル数: 見積もり=[3] / 実績=[3] / 差異=一致
- 工数: 見積もり=[2-4h] / 実績=[3h] / 差異=範囲内

### 差異の理由（大きい場合）
[差異が大きい場合は理由を記載]
```

### Phase 8: Output the review result

```markdown
## レビュー結果

### 総合判定（Status）
Approved / Approved with nits / Blocked / Question

### GitHub推奨アクション
Approve / Request changes / Comment

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

### 指摘事項（P0-P3）
1. [P0] [指摘タイトル]（該当: [file:line]）
2. [P2] [指摘タイトル]（該当: [file:line]）

### 質問（Question の場合は必須）
- [質問1]
- [質問2]

### 総評
[総評（日本語）]
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

- Approved: if no PR exists, run `/create-pr`; otherwise can merge
- Approved with nits: if no PR exists, run `/create-pr`; otherwise can merge (optionally batch-fix P2/P3)
- Blocked: fix P0/P1 -> run `/review-cycle` -> re-run `/review`
- Question: answer questions (do not guess) -> run `/review-cycle` -> re-run `/review`
