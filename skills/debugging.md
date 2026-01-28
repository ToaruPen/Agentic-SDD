# Debugging Skill

Debugging principles and systematic approaches. Language/framework-agnostic.

---

## Principles

### Reproduce first

- A bug that cannot be reproduced cannot be fixed
- Minimize reproduction steps

### Isolate the problem

- Fix one variable at a time
- Create minimal reproduction case

### Binary search approach

- Divide the problem space in half
- Identify "works up to here"

### Understand before fixing

- Understand the cause before fixing
- Do not fix by guessing

---

## Systematic Approach

### Step 1: OBSERVE

- Record symptoms accurately
- Collect error messages and stack traces
- Document what happened vs what was expected

### Step 2: HYPOTHESIZE

- Form hypotheses about the cause
- List multiple hypotheses
- Prioritize by ease of verification

### Step 3: TEST

- Verify hypotheses one at a time
- Record verification results
- Move to next hypothesis if disproven

### Step 4: FIX

- Fix once cause is identified
- Make minimal changes
- Consider side effects

### Step 5: VERIFY

- Confirm fix is effective
- Add regression test
- Check similar locations

---

## Debugging Strategies

### Print/Log Debugging

- Use case: Tracing data flow
- Method: Add logs at input/output boundaries and state change points
- Caution: Do not leave in production code

### Binary Search Debugging

- Use case: Bug somewhere in a wide range
- Method: Place checkpoint at midpoint, determine normal/abnormal, narrow to problematic half

### Rubber Duck Debugging

- Use case: Logic errors, assumptions
- Method: Explain code out loud, explain purpose of each line, notice contradictions

### Differential Debugging

- Use case: Code that used to work
- Method: Compare with working version, identify differences, verify changes one by one

---

## Common Bug Patterns

**Off-by-one**
- Symptom: Fails at boundary
- Investigation: Loop conditions, array indices

**Null/Undefined**
- Symptom: Unexpected crash
- Investigation: Initialization, return value checks

**Race condition**
- Symptom: Intermittent failure
- Investigation: Concurrent access, timing

**State mutation**
- Symptom: Unexpected values
- Investigation: Shared state, side effects

**Type coercion**
- Symptom: Invalid comparison
- Investigation: Implicit type conversion

**Resource leak**
- Symptom: Memory/connection exhaustion
- Investigation: Missing close, reference retention

---

## Checklist

### Before debugging

- [ ] Symptoms recorded accurately
- [ ] Reproduction steps established
- [ ] Expected behavior clarified
- [ ] Recent changes reviewed

### During debugging

- [ ] Verifying one hypothesis at a time
- [ ] Recording verification results
- [ ] Not fixing by guessing
- [ ] Time-boxing (try different approach if stuck)

### After fixing

- [ ] Regression test added
- [ ] Similar locations checked
- [ ] Root cause documented
- [ ] Debug code removed

---

## Anti-patterns

**Print-and-pray**
- Problem: Random log additions
- Alternative: Place logs based on hypothesis

**Fixing symptoms**
- Problem: Root cause unresolved
- Alternative: Dig until cause found

**Ignoring warnings**
- Problem: Missing problem signs
- Alternative: Investigate warnings seriously

**Debugging in production**
- Problem: High risk
- Alternative: Prioritize local reproduction

See also `skills/anti-patterns.md` for more patterns including "Batch fixes without verification".

---

## Related

- `skills/error-handling.md` - error classification and logging guidelines
- `skills/data-driven.md` - metrics-driven debugging
- `skills/testing.md` - regression testing
- `skills/anti-patterns.md` - common anti-patterns
