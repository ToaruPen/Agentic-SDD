# /tdd

Helper command to drive changes via TDD (Test-Driven Development).

This focuses on the execution loop (Red -> Green -> Refactor), but still requires a
Full estimate + explicit user approval (via `/estimation`).
User-facing output remains in Japanese.

## Usage

```
/tdd [issue-number]
```

## Flow

### Phase 0: Implementation gate (MANDATORY)

Before starting any TDD cycle, pass the implementation gates.

1. Ensure you are on the linked branch
   - Confirm current branch: `git branch --show-current`
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop
   - If multiple linked branches exist, stop and request explicit branch selection before continuing
   - If no linked branch exists, STOP and create one before starting:
      - Required: `/worktree new --issue <issue-number> --desc "<ascii short desc>"`
     - Then re-run `/tdd` inside that worktree
2. Run `/estimation` and get explicit approval
   - `/estimation [issue-number]`
   - The mode must be selected as `/tdd` (via heuristic, user choice, or operator override).

Notes:

- If an approved Full estimate already exists in this session, reference it and do not rewrite.
- Do not start Red/Green/Refactor without explicit approval.

### Phase 1: Fix the scope (SoT)

1. Read the Issue and extract AC
2. Identify related Epic/PRD
3. Clarify compatibility constraints (external interfaces that must not break)
4. Identify the test command

If required information is missing and you cannot write a failing test (Red), ask and stop.
Do not invent requirements.

### Phase 2: Turn AC into test TODOs

Split AC into TODOs (rule of thumb: 1 cycle = 1 test).

- Test design (types, AAA, coverage): `skills/testing.md`
- TDD operations (cycle, seams, legacy tactics): `skills/tdd-protocol.md`

### Phase 3: TDD cycle (Red -> Green -> Refactor)

Pick one TODO and repeat:

1. Red: write a failing test
2. Red: run tests and confirm the failure
3. Green: implement the minimum change
4. Green: confirm all tests pass
5. Refactor: improve structure while staying Green

If non-determinism exists (time/random/I-O/etc), create a seam first (see `skills/tdd-protocol.md`).

### Phase 4: Output

Summarize briefly:

- Tests added/updated (what they guarantee)
- Test command and results
- Key design decisions (seam, Extract/Sprout, etc)

Before committing:

- After implementation is complete, run `/test-review` and then `/review-cycle` automatically before committing and fix findings until it passes.
  If the change is lightweight (e.g. documentation-only updates), ask the user whether to run `/review-cycle` (skipping requires explicit approval and a recorded reason).
- Then run `/final-review` (final DoD + `/sync-docs` gate).

After `/final-review` is approved:

- Re-run `/test-review` on committed `HEAD` with `TEST_REVIEW_DIFF_MODE=range`.
- Run `/create-pr` to push and create the PR.

## Related

- `skills/tdd-protocol.md` - TDD execution protocol
- `skills/testing.md` - test design
- `.agent/commands/test-review.md` - test review preflight gate
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/impl-gate.md` - mandatory gates (estimate/test/quality)
- `.agent/commands/estimation.md` - Full estimate + approval gate
- `.agent/commands/impl.md` - normal implementation flow
- `.agent/commands/review-cycle.md` - local review loop (required before commit)
- `.agent/commands/final-review.md` - final review gate
