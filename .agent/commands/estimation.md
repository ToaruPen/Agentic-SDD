# /estimation

Create a Full estimate (11 sections) for an Issue and run the estimate review gate.

This command does not implement code.
User-facing output and artifacts remain in Japanese.

## Usage

```
/estimation [issue-number]
```

## Flow

### Phase 1: Read the Issue

1. Read the specified Issue
2. Identify the related Epic and PRD
3. Extract AC

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
task: [テスト作成・実行]
effort_range: 1-2h
confidence: Med

Task-4
task: [品質チェック（lint/typecheck等）]
effort_range: 0.5-1h
confidence: Med

total_effort_range: 3-6h
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

AC をテスト TODO に分解する（テスト設計: `skills/testing.md`）。

TDD で進める場合は `.agent/commands/tdd.md` の手順（Red → Green → Refactor）に従う（操作の詳細: `skills/tdd-protocol.md`）。

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

### Phase 2.5: Estimate review gate (MANDATORY)

Present the completed estimate to the user and get explicit approval before implementation.

Required:

1. Summarize the estimate (size/effort/confidence, and whether questions remain)
2. Ask the user to choose the implementation mode (do not recommend)
3. Ask for explicit approval to start implementation
4. If section 10 contains any open questions, stop and wait (see Phase 4)
5. If approved (and no open questions), create the local approval record (for gate enforcement):
   - Save the approved estimate to: `.agentic-sdd/approvals/issue-<n>/estimate.md`
   - Run: `python3 scripts/create-approval.py --issue <n> --mode <impl|tdd|custom>`
   - Run: `python3 scripts/validate-approval.py` (must pass)

Example (Japanese):

```text
見積もりが完成しました。

- 合計推定行数: [50-100行]
- 合計工数: [3-6h]
- 全体信頼度: [Med]
- 確認事項: [なし / あり（要回答）]

実装モードを選んでください（推奨は付けません）:
1. /impl（通常）で進める
2. /tdd（Red→Green→Refactor）で進める
3. 自由記述（条件/相談）

承認: この見積もり内容で実装を開始してよいですか？（Yes/No）
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
4. Re-run Phase 2.5 (review + approval)

### Phase 5: Output

When Phase 2.5 is approved, stop and point to the next command:

- If the user chose normal mode: run `/impl`
- If the user chose strict TDD: run `/tdd`

## N/A examples

- 4. DB影響: N/A（本Issueはフロントエンドのみ、DB操作なし）
- 5. ログ出力: N/A（ログ変更なし。既存のエラーログで十分）
- 6. I/O一覧: N/A（外部I/Oなし。内部計算処理のみ）
- 7. リファクタ候補: N/A（新規コードのため候補なし）
- 8. フェーズ分割: N/A（単一フェーズ。推定50行以下）

## Related

- `skills/estimation.md` - estimation skill details
- `skills/testing.md` - test strategy and design
- `skills/tdd-protocol.md` - TDD execution protocol
- `.agent/commands/impl.md` - normal implementation flow
- `.agent/commands/tdd.md` - strict TDD execution loop
- `.agent/rules/impl-gate.md` - mandatory gates (estimate/test/quality)
- `.agent/rules/dod.md` - Definition of Done

## Next command

After approval, run `/impl` or `/tdd`.
