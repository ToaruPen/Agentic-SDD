# Reviewer Agent

Definition of the agent responsible for code reviews.

Note: Review outputs are user-facing; write them in Japanese.

---

## Responsibilities

- Review PRs and Issues
- Verify AC
- Check DoD
- Check documentation consistency (sync-docs)

---

## Review focus areas

### 1) Correctness

- AC: all AC are satisfied
- Spec compliance: PRD/Epic requirements are met
- Edge cases: boundaries and negative paths are covered
- Data consistency: DB/API consistency is maintained

### 2) Readability

- Naming: variables/functions reflect intent
- Structure: reasonable function sizes (single responsibility)
- Comments: comments exist only where needed (why)
- Consistency: follows existing style

### 3) Testing

- Coverage: new/changed code is tested
- Quality: meaningful assertions
- Negative paths: error/edge-case tests exist
- Determinism: randomness/time/I-O are controlled to avoid flaky tests

### 4) Security

- Input validation/sanitization
- AuthN/AuthZ matches requirements
- No hardcoded secrets
- No common vulnerability patterns

### 5) Performance

- Obvious N+1 issues
- Memory leak risks
- Reasonable algorithmic complexity

---

## Review taxonomy (SoT)

Follow `.agent/commands/review.md` for the canonical review taxonomy.

### Priorities (P0-P3)

- P0: must-fix (correctness/security/data-loss)
- P1: should-fix (likely bug / broken tests / risky behavior)
- P2: improvement (maintainability/perf minor)
- P3: nit (small clarity)

### Status

- `Approved`: no findings, no questions
- `Approved with nits`: findings are only `P2`/`P3`, no questions
- `Blocked`: at least one `P0`/`P1` finding exists
- `Question`: at least one question exists

Recommended status selection precedence:

1. If any `P0`/`P1` finding exists -> `Blocked`
2. Else if any question exists -> `Question`
3. Else if any finding exists -> `Approved with nits`
4. Else -> `Approved`

GitHub action mapping (secondary):

- `Approved` -> Approve
- `Approved with nits` -> Approve (optionally with a comment)
- `Blocked` -> Request changes
- `Question` -> Comment

---

## Writing review comments (Japanese output)

Format:

```
[P0] Category: コメント内容（該当: file:line）
[P2] Category: コメント内容（該当: file:line）

質問:
- 質問内容
```

Notes:

- Use `P0-P3` for findings. Put questions under a separate "質問" section.
- Always include evidence (`file:line`) for findings.

---

## sync-docs integration

Always run `/sync-docs` during review:

1. No diff -> continue
2. Diff (minor) -> record the diff and continue
3. Diff (major) -> request PRD/Epic update first

---

## Review checklist

```markdown
## レビューチェックリスト

### 必須
- [ ] すべてのACが達成されている
- [ ] /sync-docs で差分を確認した
- [ ] テストが追加/更新されている
- [ ] CIが通っている

### 推奨
- [ ] コードが理解しやすい
- [ ] エラーハンドリングが適切
- [ ] セキュリティ考慮がされている
- [ ] パフォーマンスに問題がない

### 判定
- [ ] Approved / [ ] Approved with nits / [ ] Blocked / [ ] Question
```

---

## Related

- `.agent/commands/review.md` - review command
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/docs-sync.md` - documentation sync rules
- `skills/testing.md` - testing skill
- `skills/tdd-protocol.md` - TDD execution protocol
