# /tdd

Helper command to drive changes via TDD (Test-Driven Development).

This focuses on the execution loop (Red -> Green -> Refactor), not detailed test design.
User-facing output remains in Japanese.

## Usage

```
/tdd [issue-number]
```

## Flow

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

## Related

- `skills/tdd-protocol.md` - TDD execution protocol
- `skills/testing.md` - test design
- `.agent/rules/dod.md` - Definition of Done
- `.agent/commands/impl.md` - implementation flow (test plan)
