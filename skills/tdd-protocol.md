# TDD Execution Protocol

Operational protocol for TDD (Test-Driven Development) to make changes safely.

The goal of unit tests here is to keep the project moving: detect regressions while preserving
the ability to change code.

This skill covers "how to run the loop" (operations), not detailed test design.
For test design (types, AAA, coverage), see `skills/testing.md`.

---

## When to use

- Any change work: new feature, bug fix, refactor, legacy modification
- Codebases with weak/no tests where you need a safe foothold

## When not to use

- Pure investigation/explanation (no change)
- You cannot run tests and the request explicitly demands alternatives (manual verification/design review)

---

## Test Philosophy

### Valid test conditions

For a test to be considered "valid evidence", both conditions are required:

1. **Failure reproducibility**: Test must fail before the change
   - Proves the test can correctly detect the problem
   - A test that always passes has no verification capability

2. **Correction assurance**: Test must pass after the change
   - Proves the implemented change solved the problem
   - Before/After state change must be observable

### Invalid tests

- Passing before the change -> Verifies nothing
- Failing after the change -> Fix is incomplete
- Non-deterministic pass/fail -> Lacks reproducibility (add seams)

### Required sequence

1. Write failing test
2. Confirm test fails (Before record)
3. Implement fix
4. Confirm test passes (After record)

---

## Goals

1) Detect regressions
2) Keep tests resilient to refactors (avoid false positives)
3) Get feedback in short loops
4) Keep the system maintainable (readable, robust)

---

## Principles and constraints

- Do not change external behavior that is not required by the spec (tests lock intent)
- Do not refactor while Red (only refactor while Green)
- Avoid over-coupling tests to implementation details (private structure, call counts)
- Non-determinism (randomness/time/concurrency/I-O/external APIs) must be controlled; create seams

---

## Required inputs (and what to do when missing)

Preferably obtain:

- Goal: desired behavior (AC)
- Target (repo/dir), language, test command
- Compatibility constraints (external interfaces you must not break)

If something is missing:

- State assumptions explicitly
- If you cannot proceed safely, ask and stop (do not invent requirements)

---

## Deliverables

- Added/updated tests (minimal set that expresses intent)
- Production code changes (minimum needed for Green)
- Test commands executed and results (what was verified)

---

## Workflow

### 0) Scaffolding (especially for legacy)

- If tests are missing/thin, add one coarse "protective" test first (happy path is OK)
- Find an observable boundary (public API, request/response, persisted state)
- If tests are flaky, fix non-determinism first by introducing seams

### 1) TDD cycle (Red -> Green -> Refactor)

1. Break the goal into small TODOs
2. Pick one TODO and write a failing test (Red)
3. Run tests and confirm the failure (evidence)
4. Add the minimum implementation to satisfy the test
5. Confirm all tests pass (Green)
6. Refactor while staying Green
7. Repeat

### 2) Minimum test-design rules (stability first)

- Assert observable behavior first (return values, public API results, persisted state, emitted messages)
- Name tests by behavior (avoid direct coupling to function names)
- Use AAA (Arrange/Act/Assert) for readability (see `skills/testing.md`)

### 3) Controlling non-determinism (Seams / Humble Object)

Sources of flakiness:

- randomness, time, UUID, concurrency, network, filesystem, env vars, global state

Mitigations:

- Create seams to inject behavior (args/DI/environment objects)
  - e.g. inject `now()`, `uuid()`, `nextIndex()`, `httpClient`
- In tests, pass fixed values or fakes
- Keep I-O/framework details thin; keep core logic testable (Humble Object)
- If using PBT (generative tests), fix randomness (seed) and keep counterexamples as concrete regression tests

### 4) Legacy tactics (Extract vs Sprout)

- Extract: add coarse protection tests, keep Green, and extract logic out
- Sprout: avoid deep edits; grow new code under test and connect at boundaries

Heuristics:

- If you can protect behavior with a minimal test, prefer Extract
- If it is too risky/time-constrained, prefer Sprout to limit blast radius

### 5) Separate domain model from details

- Split "details" (framework/SDK/I-O) from "core logic"
- Plain models tend to yield stable unit tests

Incremental approach:

1. Create a new model class and grow it via TDD
2. Move logic from handlers into the model (keep coarse tests Green)
3. Reduce framework dependency via dump/restore, adapters, etc
4. Let the model own state transitions; shrink handler branching

### 6) Separate facts from derived information

- Persist facts (data) as state
- Derive "information" from facts via computation
- Tests should verify consistent fact -> derived info behavior

---

## Checklists

Pre-flight:

- [ ] You can state the goal (AC) in one sentence
- [ ] You know the test command (ask if unknown)
- [ ] You understand what external interface must not change

Per cycle:

- [ ] Red: the failing test expresses behavior
- [ ] Green: minimal change
- [ ] Refactor: improved structure while staying Green

Before submit:

- [ ] All tests are stable Green (no flakes)
- [ ] Tests are not overly coupled to implementation details
- [ ] Non-determinism is injected/fixed
- [ ] Run `/review-cycle` after implementation (same as `/impl`), fix findings until it passes
- [ ] Then run `/final-review` as the final DoD + `/sync-docs` gate

---

## Mini examples

Example 1: randomness breaks expectations

- Symptom: expectations vary due to RNG
- Fix: inject `nextIndex()` and return a fixed value in tests

Example 2: handler logic becomes unmaintainable

- Symptom: branching grows and breaks under spec changes
- Fix: create a domain model (e.g. `Session`); TDD the model; keep handlers as I/F mapping

Example 3: storing derived info causes inconsistency

- Symptom: multiple places update scores/state and drift
- Fix: store facts (event log) and derive scores from facts

---

## Related

- `skills/testing.md` - test design
- `skills/error-handling.md` - error handling (negative-path tests)
- `skills/estimation.md` - estimation (test plan section)
- `.agent/rules/dod.md` - Definition of Done
- `.agent/commands/impl.md` - implementation flow
