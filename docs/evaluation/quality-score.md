# Quality Score (Health Check)

This document is a template for tracking the "quality health" of an Agentic-SDD project over time.

Important:

- This is **NOT a Gate (pass/fail)**. Pass/fail decisions belong to [`docs/evaluation/quality-gates.md`](quality-gates.md)
- Scores are used for investment decisions, improvement prioritization, and GC recovery strategy
- See [`docs/sot/README.md`](../sot/README.md) for SoT priority and reference rules

---

## Update Frequency / Owners

- Recommended frequency: weekly (or per release)
- Expected owners:
  - Human: primary owner (manual updates)
  - GC: periodic collection (auto-reflects some lint/link results)
  - External harness: external orchestration layer aggregates and posts (optional)

---

## Evaluation Axes (Example)

Each axis is scored 0-3 with at least one piece of evidence.

- 0: None / untrackable
- 1: Partial / occasional
- 2: Moderate / ongoing
- 3: Sufficient / systematic

### Axis A: Testing (Regression / Reliability)

- Aspect: Preventing regression of critical logic, failure reproducibility, test evidence trail
- Evidence examples: `tests.txt`, CI logs, `/review-cycle` `Tests:` output

### Axis B: Spec Consistency (SoT: PRD/Epic/Implementation)

- Aspect: Whether PRD/Epic/implementation can be traced without contradiction, whether inputs are deterministic
- Evidence examples: `/sync-docs` results, uniqueness of SoT references

### Axis C: Type Safety / Static Analysis (if applicable)

- Aspect: Typecheck practices, suppression of dangerous workarounds (`as any`, etc.)
- Evidence examples: typecheck command output, CI logs

### Axis D: Observability (Logs / Errors / Audit)

- Aspect: Whether root cause can be identified on failure, whether error classification exists
- Evidence examples: `.agent/rules/observability.md`, application log design

### Axis E: Security

- Aspect: Auth/authz/secrets, dependency vulnerabilities, dangerous pattern suppression
- Evidence examples: `.agent/rules/security.md`, dependency audit

### Axis F: Performance / Availability (if applicable)

- Aspect: Whether measurement and improvement cycles are running when SLO/performance requirements exist
- Evidence examples: `.agent/rules/performance.md`, measurement results

### Axis G: Documentation Health

- Aspect: Broken links/placeholders, un-updated copies from templates
- Evidence examples: `scripts/agentic-sdd/lint-sot.py`, periodic GC

---

## Gate-Linked Metrics (Periodic Observation)

This section is a periodic observation template that bridges the Gate pass/fail (binary) from [`quality-gates.md`](quality-gates.md) with the quality scores (0-3 gradient) above.

Key distinction:

- **Gate (pass/fail)**: Mandatory checkpoint. Cannot proceed to the next stage without Pass. Definitions owned by [`quality-gates.md`](quality-gates.md)
- **Gate-linked metrics (this section)**: Health signal. Observe Gate pass rates over time as input for investment decisions and improvement prioritization. NOT a substitute for pass/fail

### YYYY-MM-DD

Record each Gate's Pass/Fail with evidence links. Update frequency is the same as quality scores (weekly or per release).
Append a table under each dated heading (append-only, same as score recording).

| Gate | Pass/Fail | Evidence Link | Note |
| --- | --- | --- | --- |
| Gate 0: Worktree preconditions are satisfied |  |  |  |
| Gate 1: SoT resolution is deterministic |  |  |  |
| Gate 2: Change evidence (diff) is unambiguous |  |  |  |
| Gate 3: Quality checks (tests/lint/typecheck) are executed with evidence |  |  |  |
| Gate 4: Local iterative review (`review.json`) is schema-compliant |  |  |  |
| Gate 5: Final review (DoD + docs sync) passes |  |  |  |

Evidence link examples: CI log URL, path to `review.json`, `/review-cycle` output snippet

> **Sample entry** — The following is a reference sample. In production use, delete this block and copy the template above.

### 2025-01-15 (sample)

| Gate | Pass/Fail | Evidence Link | Note |
| --- | --- | --- | --- |
| Gate 0: Worktree preconditions are satisfied | Pass | `validate-worktree.py` run log | Issue #123 worktree OK |
| Gate 1: SoT resolution is deterministic | Pass | `/sync-docs` no diff | PRD/Epic/implementation all consistent |
| Gate 2: Change evidence (diff) is unambiguous | Pass | `review.json` `DiffMode: range` | Uniquely identified via range diff |
| Gate 3: Quality checks (tests/lint/typecheck) are executed with evidence | Pass | CI run #42 log | lint, typecheck, test all passed |
| Gate 4: Local iterative review (`review.json`) is schema-compliant | Fail | `.agentic-sdd/reviews/issue-123/review.json` | status: Blocked (P1 unresolved) |
| Gate 5: Final review (DoD + docs sync) passes | Fail | — | Not executed due to Gate 4 Blocked |

### Measurement Timing and Criteria

- **Measurement timing**: Record at the same timing as quality score updates (weekly or per release)
- **Criteria**: Refer to [`quality-gates.md`](quality-gates.md) for each Gate's Pass/Fail definition. This section does not redefine criteria

---

## Score Recording (Time Series)

Append entries below (append-only).

### YYYY-MM-DD

| Axis | Score | Evidence | Note |
| --- | ---: | --- | --- |
| A: Testing |  |  |  |
| B: SoT |  |  |  |
| C: Type Safety |  |  |  |
| D: Observability |  |  |  |
| E: Security |  |  |  |
| F: Performance/Availability |  |  |  |
| G: Documentation |  |  |  |

Notes:

- Do not use as a Gate (not a substitute for pass/fail). Pass/fail decisions belong to [`quality-gates.md`](quality-gates.md)
- When a score drops, write "why" (GC, large-scale change, debt surfacing, etc.)
