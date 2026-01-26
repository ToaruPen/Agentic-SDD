# Implementation Gate Rules

Mandatory gates for implementing an Issue.

These gates exist to prevent skipping required phases (estimate, test plan, quality checks)
and to make decision points explicit.

User-facing output remains in Japanese.

---

## Gate 0: Mode selection (required)

- [ ] Ask the user which mode to use (do not choose on your own):
  1. /impl (normal)
  2. /tdd (strict Red -> Green -> Refactor loop)
  3. Custom (user-written conditions)
- [ ] Record the user's choice.

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
  - lint / format / typecheck (when applicable)
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
