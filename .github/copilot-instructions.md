# Copilot Custom Instructions

This project is **Agentic-SDD** — a workflow template for AI-driven, spec-driven development.
User-facing outputs (PRDs, Epics, Issues, PRs, review comments) are written in Japanese.

## Review Priorities (supplement to defaults)

Copilot already covers bugs, security, performance, and readability.
Focus additionally on these project-specific concerns:

### Testing Quality

- New or changed code must have tests with **meaningful assertions** (not just "no error thrown").
- Negative paths and edge cases must be explicitly tested.
- Tests must be **deterministic**: randomness, time, and I/O should be controlled (no flaky tests).
- Empty catch blocks `catch(e) {}` and assertion-less tests are not acceptable.

### Type Safety

- Never suppress type errors with `as any`, `@ts-ignore`, or `@ts-expect-error`.
- Prefer explicit types over implicit `any`.

### Error Handling

- Errors must fail fast with explicit, actionable messages.
- No silent fallbacks or dummy/no-op implementations.
- Error messages should include: cause, impact, and suggested next action.

### Spec Compliance (when PR references an Issue)

- If the PR body links to an Issue, verify that all Acceptance Criteria (AC) listed in the Issue are satisfied by the changes.
- Do not add features or behavior not documented in the linked Issue/PRD/Epic.
- Flag changes that go beyond the stated scope.

### Commit & PR Hygiene

- Commits should follow **Conventional Commits**: `type(scope): description` (types: feat, fix, docs, style, refactor, test, chore).
- Each commit should be atomic — one logical change per commit.
- Do not mix unrelated changes in one commit.

### Evidence Requirements

- Bug fix PRs should include a test that would have caught the bug (regression test).
- Performance improvement claims require before/after measurements.
- "Fixed" or "Improved" without evidence is not acceptable.

### Code Style

- Prefer simplicity (YAGNI, KISS, DRY).
- Comments should explain **why**, not **what**.
- Functions should be small and focused (single responsibility).
- Match existing code style and patterns in the repository.
