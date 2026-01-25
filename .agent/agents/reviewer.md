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

## Review taxonomy and outputs (SoT)

- Follow `.agent/commands/review.md` for canonical P0-P3 and status rules.
- Always include evidence (`file:line`) for findings.
- Always run `/sync-docs` during review (rules: `.agent/rules/docs-sync.md`).
- For DoD expectations, follow `.agent/rules/dod.md`.

---

## Related

- `.agent/commands/review.md` - review command
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/docs-sync.md` - documentation sync rules
- `skills/testing.md` - testing skill
- `skills/tdd-protocol.md` - TDD execution protocol
