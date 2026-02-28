# Implementation Gate Rules

Mandatory gates for implementing an Issue.

These gates exist to prevent skipping required phases (estimate, test plan, quality checks)
and to make decision points explicit.

User-facing output remains in Japanese.

---

## Gate -1: Worktree (required)

- [ ] Before `/estimation`, create and use a per-Issue branch/worktree via `/worktree new`.
- [ ] If no linked branch exists for the Issue, STOP and create one before estimating.

Rationale:

- Estimation/implementation must be anchored to a deterministic branch/worktree state.

## Gate 0: Mode selection (required)

- [ ] The agent selects the mode using deterministic heuristics:
  - Default: `/impl` (normal implementation).
  - Select `/tdd` when ANY of these conditions are met:
    1. The Issue is a bug fix with a reproducible failing test.
    2. The Issue AC explicitly requires TDD.
    3. The operator/user explicitly requests `/tdd`.
  - Select `custom` only when the operator/user explicitly provides custom conditions.
- [ ] Record the selection in the approval record:
  - `mode`: impl | tdd | custom
  - `mode_source`: agent-heuristic | user-choice | operator-override
  - `mode_reason`: free-text explanation of why this mode was selected

Implementation note:

- The mode selection is performed in the `/estimation` review gate.

Note:

- Regardless of mode, tests must deterministically verify the Acceptance Criteria (AC).

---

## Gate 1: Estimate gate (required)

- [ ] Full estimate (11 sections) is fully written.
- [ ] Present the estimate to the user.
- [ ] If section 10 contains any open questions, stop and wait for answers.
- [ ] Get explicit approval before starting implementation.

Implementation note:

- Use `/estimation` to create the Full estimate and run the approval gate.

---

## Gate 2: Test strategy gate (required)

- [ ] Section 9 (test plan) is reviewed with the user.
- [ ] Decide the test command(s).
  - If unknown, identify them from the repository and confirm.
- [ ] Identify non-determinism risks (time/random/I-O/etc) and plan seams when needed.

---

## Gate 3: Quality gate (post-implementation, required)

 - [ ] Run project-defined quality checks:
   - tests (required)
   - lint / format / typecheck (required)
  - [ ] If any check cannot be run, report:
    - reason
    - impact
    - what was done instead (if any)
    - and ask for explicit approval to proceed.

---

## Development loop (single-step)

Changes must follow this loop, one at a time:

1. Run (confirm current state)
2. Compare with expected result
3. Identify discrepancy (one only)
4. Implement fix (one only)
5. Verify immediately -> if fail, return to step 3
6. Success -> move to next issue

Prohibited: "Verify 5 fixes together" -> makes it unclear which one broke things

This loop applies to each change. Batching multiple fixes leads to exponential debugging time.

---

## Violation policy

If a gate is skipped:

1. Stop implementation.
2. Return to the skipped gate and complete it.
3. Report to the user what was skipped and what changed.

---

## Related

- `.agent/commands/estimation.md`
- `.agent/commands/impl.md`
- `.agent/commands/tdd.md`
- `.agent/rules/dod.md`
- `skills/testing.md`
- `skills/tdd-protocol.md`
