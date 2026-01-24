# /impl

Implement an Issue.

You must create a Full estimate (11 sections) before starting implementation.
User-facing output and artifacts remain in Japanese.

## Usage

```
/impl [issue-number]
```

## Flow

### Phase 1: Read the Issue

1. Read the specified Issue
2. Identify the related Epic and PRD
3. Extract AC
4. Check work status (required)
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop
   - (Optional) For each linked branch, check PRs: `gh pr list --head "<branch>" --state all`
   - If no linked branch exists, create one *before* starting the estimate
     - Recommended: `/worktree new --issue <issue-number> --desc "<ascii short desc>"` and re-run `/impl` inside that worktree
     - Alternative (no worktree): `gh issue develop <issue-number> --name "<branch>" --checkout`

### Phase 2: Create the Full estimate (required)

Write all 11 sections. If a section is not applicable, write `N/A (reason)`.

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

### Phase 3: Confidence rules

- High: similar prior work, clear scope (range can be tight)
- Med: some uncertainty, but likely within range (range slightly wider)
- Low: high uncertainty / Unknowns remain (double the range or ask questions first)

### Phase 4: Resolve open questions

If section 10 contains questions:

1. Ask the user (in Japanese)
2. Wait for answers
3. Update the estimate accordingly

### Phase 5: Start implementation

Summarize the estimate and any open questions. If there are open questions, stop.

Example (Japanese):

```text
見積もりが完成しました。

- 合計推定行数: [50-100行]
- 合計工数: [2.5-5h]
- 全体信頼度: [Med]
- 確認事項: [なし / あり（要回答）]
```

### Phase 6: Implement

1. Create a branch (see `.agent/rules/branch.md`)
2. Implement per the estimate
3. Add/update tests

### Phase 6.5: Local review (required)

Run `/review-cycle` before committing:

1. Execute review checks
2. Fix any issues found
3. Re-run until pass

### Phase 7: Commit

1. Commit in a working state (see `.agent/rules/commit.md`)

### Phase 8: Finish

Report actual vs estimated, and suggest next steps.

Example (Japanese):

```text
実装が完了しました。

- 実際の行数: [75行]（見積もり: 50-100行 → 範囲内）
- 実際の工数: [3h]（見積もり: 2.5-5h → 範囲内）

次のステップ:
1. /review を実行して最終セルフレビュー
2. PRを作成
```

## N/A examples

- 4. DB影響: N/A（本Issueはフロントエンドのみ、DB操作なし）
- 5. ログ出力: N/A（ログ変更なし。既存のエラーログで十分）
- 6. I/O一覧: N/A（外部I/Oなし。内部計算処理のみ）
- 7. リファクタ候補: N/A（新規コードのため候補なし）
- 8. フェーズ分割: N/A（単一フェーズ。推定50行以下）

## Options

- `--estimate-only`: write the estimate only (do not implement)
- `--skip-confirm`: skip any start-confirm step

## Related

- `skills/estimation.md` - estimation skill details
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/issue.md` - issue granularity rules

## Next command

After implementation, run `/review`.
