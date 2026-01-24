# Testing Skill

Guidelines for test strategy, test types, and coverage.

Language/framework-agnostic; concept-based.

This document covers test design and writing. For TDD operations (Red/Green/Refactor), seams,
and legacy tactics, see `skills/tdd-protocol.md`.

---

## Test pyramid (rule of thumb)

- Unit: ~70% (fast, low maintenance)
- Integration: ~20% (moderate)
- E2E: ~10% (slow, high maintenance)

---

## Test types

### Unit tests

Scope: a single function/class/module.

Model: provide inputs, assert outputs/side-effects. Mock external dependencies.

Characteristics:

- Mock external dependencies
- Fast
- Cover boundaries and negative paths

### Integration tests

Scope: interactions between multiple components.

Model: verify combined behavior (e.g. API + DB).

Characteristics:

- Use real or test instances of DB/external systems
- Verify cross-component behavior
- Slower than unit, closer to reality

### E2E tests

Scope: end-to-end user flows.

Model: verify key user scenarios from input to output.

Characteristics:

- Closest to real behavior
- Slowest
- Keep to critical flows only

---

## Writing tests

### AAA pattern

```
// Arrange
const user = createTestUser();
const repository = new UserRepository();

// Act
const result = await repository.save(user);

// Assert
expect(result.id).toBeDefined();
expect(result.name).toBe(user.name);
```

### Naming tests

```
// Pattern 1: should-when
"should return error when email is invalid"

// Pattern 2: given-when-then
"given invalid email, when saving user, then returns validation error"
```

---

## Coverage

Coverage types:

- Line coverage (target guideline: 80%+)
- Branch coverage (target guideline: 70%+)
- Function coverage (target guideline: 90%+)

Coverage != quality.

```
// 100% coverage but meaningless (no assertion)
test("adds numbers", () => {
  add(1, 2);
});

// Meaningful assertions
test("adds numbers correctly", () => {
  expect(add(1, 2)).toBe(3);
  expect(add(-1, 1)).toBe(0);
  expect(add(0, 0)).toBe(0);
});
```

What can be excluded:

- Generated code
- Config files
- Type-only definitions

What should not be excluded:

- Business logic
- Error handling
- Important branching logic

---

## What to test (priority)

Must test:

- Business logic (high impact)
- Validation (often security-related)
- Error handling (behavior under failure)
- Boundaries (high bug density)

Consider testing:

- External integrations
- Complex branching
- Performance-critical code (detect regressions)

May not need tests:

- Trivial getters/setters
- Framework internals already tested
- Short-lived throwaway code (low ROI)

---

## Test data

Approaches:

- Factory functions (generate data)
- Fixture files (static data)
- Seed data (DB baseline)

Principles:

- Tests are independent
- Setup/teardown per test
- Never use production data

---

## Mocks / stubs

When to use:

- Mock: verify calls/interactions
- Stub: return fixed values
- Spy: run real code while recording calls
- Fake: lightweight replacement implementation

Notes:

- Over-mocking diverges from reality
- Mock external dependencies only (do not mock core logic)
- Mock outputs should match real APIs

---

## Checklists

Planning:

- [ ] Test priorities are decided
- [ ] Test types are chosen (Unit/Integration/E2E)
- [ ] Coverage expectations are set

Implementation:

- [ ] Uses AAA
- [ ] Names express behavior
- [ ] Has both happy and negative paths
- [ ] Boundaries are tested
- [ ] Tests are independent

Maintenance:

- [ ] Unneeded tests removed
- [ ] Broken tests not left behind
- [ ] Runtime is acceptable

---

## Anti-patterns

- No assertions: verifies nothing -> add meaningful assertions
- Multiple concerns in one test: unclear failures -> split tests
- Test order dependency: flaky behavior -> isolate each test
- Using production data: security risk -> generate test data
- Leaving slow tests: CI slows down -> optimize or separate
- Coverage worship: inflates meaningless tests -> focus on quality

---

## Related

- `skills/error-handling.md` - error handling (negative-path tests)
- `skills/api-endpoint.md` - API design (API tests)
- `skills/tdd-protocol.md` - TDD execution protocol
- `.agent/rules/dod.md` - Definition of Done
