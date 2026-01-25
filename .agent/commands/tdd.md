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
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop
   - If no linked branch exists, create one before starting:
     - Recommended: `/worktree new --issue <issue-number> --desc "<ascii short desc>"`
     - Alternative (no worktree): `gh issue develop <issue-number> --name "<branch>" --checkout`
2. Run `/estimation` and get explicit approval
   - `/estimation [issue-number]`
   - When prompted for the implementation mode, choose `/tdd`.

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

- Run `/review-cycle` (required) and fix findings until it passes.
- Then run `/review` (final DoD + `/sync-docs` gate).

After `/review` is approved:

- Run `/create-pr` to push and create the PR.

## Related

- `skills/tdd-protocol.md` - TDD execution protocol
- `skills/testing.md` - test design
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/impl-gate.md` - mandatory gates (estimate/test/quality)
- `.agent/commands/estimation.md` - Full estimate + approval gate
- `.agent/commands/impl.md` - normal implementation flow
- `.agent/commands/review-cycle.md` - local review loop (required before commit)
- `.agent/commands/review.md` - final review gate
