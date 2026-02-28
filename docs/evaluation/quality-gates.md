# Quality Gates

This document lists Agentic-SDD quality gates in a referenceable form (what is Pass/Fail).

SoT index: [`docs/sot/README.md`](../sot/README.md) — refer to this index for SoT priority, reference rules, and responsibility boundaries.

Goals:
- Define stable and deterministic pass/fail criteria
- Ensure the next action is always clear on failure

---

## Gate List (Minimum)

### Gate 0: Worktree preconditions are satisfied

- Pass: For Issue branches (branch name includes `issue-<n>`), work is done in a linked worktree
- Fail: Work is done without a worktree (for example, `.git/` remains a directory)

Evidence (implementation/spec):

- enforcement: `scripts/agentic-sdd/validate-worktree.py`
- requirements (spec): `.agent/commands/estimation.md`, `.agent/rules/impl-gate.md`

### Gate 1: SoT resolution is deterministic

SoT priority and reference rules are defined in [`docs/sot/README.md`](../sot/README.md).

- Pass: PRD/Epic/diff references resolve uniquely (and when `docs/research/**/<YYYY-MM-DD>.md` exists, its contract fields/stop conditions are also satisfied)
- Fail: references are ambiguous, empty, placeholder-based, or required fields are missing in `docs/research/**/<YYYY-MM-DD>.md`

Evidence (implementation/spec):
- SoT index: [`docs/sot/README.md`](../sot/README.md)
- `/sync-docs`: `.agent/commands/sync-docs.md`
- input resolution: `scripts/agentic-sdd/resolve-sync-docs-inputs.py`
- /research contract lint: `scripts/agentic-sdd/lint-sot.py`, `.agent/commands/research.md`

### Gate 2: Change evidence (diff) is unambiguous

- Pass: The review target diff is deterministically selected (no contradiction among staged/worktree/range)
- Fail: The target is ambiguous (for example, both staged and worktree diffs are present)

Evidence (spec):
- `/review-cycle`: `.agent/commands/review-cycle.md`

### Gate 3: Quality checks (tests/lint/typecheck) are executed with evidence

- Pass: executed commands and their results are recorded
- Fail: no evidence is recorded

Exception:
- If tests cannot be run, record `not run: <reason>` and obtain approval

Evidence (spec):
- DoD: `.agent/rules/dod.md`
- required `/review-cycle` test input (`TEST_COMMAND` or `TESTS`): `.agent/commands/review-cycle.md`

### Gate 4: Local iterative review (`review.json`) is schema-compliant

- Pass: `review.json` satisfies the schema and additional constraints, and status is `Approved` or `Approved with nits`
- Fail: invalid JSON, schema mismatch, or status is `Blocked`/`Question`

Evidence (implementation/spec):
- schema: `.agent/schemas/review.json`
- validation: `scripts/agentic-sdd/validate-review-json.py`
- `/review-cycle` output contract: `.agent/commands/review-cycle.md`

### Gate 5: Final review (DoD + docs sync) passes

- Pass: `/final-review` is Approved
- Fail: DoD not met, docs sync mismatch, or unresolved questions

Evidence (spec):
- `/final-review`: `.agent/commands/final-review.md`
- docs sync rule: `.agent/rules/docs-sync.md`

---

## Gate Handling (Fail-Closed)

- Do not fill unclear inputs (references/diff/evidence) by guessing
- Treat empty/invalid JSON as Blocked-equivalent and require a concrete next action (fix or provide missing information)

---

## Non-Gate Evaluation (Health Signals)

Use this for investment decisions and GC recovery strategy, not for pass/fail.
This document (`quality-gates.md`) defines **pass/fail criteria**, while [`quality-score.md`](quality-score.md) is for **improvement measurement**. They have separate responsibilities.

- Quality score template: [`docs/evaluation/quality-score.md`](quality-score.md)
- Gate-linked metrics (periodic observation): [`docs/evaluation/quality-score.md` "## Gate-Linked Metrics (Periodic Observation)" section](quality-score.md#gate-linked-metrics-periodic-observation)
