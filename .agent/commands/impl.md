# /impl

Implement an Issue (normal mode).

You must run `/estimation` (Full estimate + explicit user approval) before starting implementation.
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
4. Check work status (required; worktree mandatory)
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop (switch into the linked worktree)
   - (Optional) For each linked branch, check PRs: `gh pr list --head "<branch>" --state all`
   - If no linked branch exists, STOP and create one *before* estimation/implementation:
     - Required: `/worktree new --issue <issue-number> --desc "<ascii short desc>"`
     - Then re-run `/impl` inside that worktree

### Phase 2: Run `/estimation` (required)

Run:

```
/estimation [issue-number]
```

Stop conditions:

- If the estimate is not approved: stop.
- If section 10 has open questions: stop and wait for answers (then re-run `/estimation`).
- If the user chose strict TDD mode: stop and run `/tdd [issue-number]` instead.

Note:

- If an approved estimate already exists for this Issue (and the approval gate passes), you can skip rewriting it and proceed to implementation.

### Phase 3: Implement

1. Ensure you are on the linked branch (created in Phase 1; see `.agent/rules/branch.md`)
2. Implement per the approved estimate
3. Add/update tests per the test plan

### Phase 4: Local review (required)

After implementation is complete, run `/test-review` then `/review-cycle` automatically before committing.
If the change is lightweight (e.g. documentation-only updates), ask the user whether to run `/review-cycle` (skipping requires explicit approval and a recorded reason).

1. Execute review checks
2. Fix any issues found
3. Re-run until pass

### Phase 5: Commit

1. Commit in a working state (see `.agent/rules/commit.md`)
2. Before `/create-pr`, re-run `/test-review` on committed `HEAD` with `TEST_REVIEW_DIFF_MODE=range`

### Phase 6: Finish

Report actual vs estimated, and suggest next steps.

Example (Japanese):

```text
実装が完了しました。

- 実際の行数: [75行]（見積もり: 50-100行 → 範囲内）
- 実際の工数: [3h]（見積もり: 3-6h → 範囲内）

次のステップ:
1. /final-review を実行して最終セルフレビュー
2. /create-pr を実行して push + PR作成
```

## Related

- `.agent/commands/estimation.md` - create a Full estimate + approval gate
- `.agent/commands/tdd.md` - strict TDD execution loop
- `.agent/commands/test-review.md` - test review preflight gate
- `.agent/commands/review-cycle.md` - local review loop
- `.agent/commands/final-review.md` - final review gate
- `.agent/rules/branch.md` - branch rules
- `.agent/rules/commit.md` - commit rules
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/impl-gate.md` - mandatory gates (estimate/test/quality)
- `.agent/rules/issue.md` - issue granularity rules

## Next command

After implementation, run `/final-review`.
