# Debugging Skill

Debugging principles and systematic approaches. Language/framework-agnostic.

---

## Principles

1. **Reproduce first**
   - A bug that cannot be reproduced cannot be fixed
   - Minimize reproduction steps

2. **Isolate the problem**
   - Fix one variable at a time
   - Create minimal reproduction case

3. **Binary search approach**
   - Divide the problem space in half
   - Identify "works up to here"

4. **Understand before fixing**
   - Understand the cause before fixing
   - Do not fix by guessing

---

## Systematic Approach

### OBSERVE

- Record symptoms accurately
- Collect error messages, stack traces
- Document "what happened" vs "what was expected"

### HYPOTHESIZE

- Form hypotheses about the cause
- List multiple hypotheses
- Prioritize by ease of verification

### TEST

- Verify hypotheses one at a time
- Record verification results
- Move to next hypothesis if disproven

### FIX

- Fix once cause is identified
- Make minimal changes
- Consider side effects

### VERIFY

- Confirm fix is effective
- Add regression test
- Check similar locations

---

## Debugging Strategies

### Print/Log Debugging

Use case: Tracing data flow
Method:
  - Add logs at input/output boundaries
  - Add logs at state change points
Caution: Do not leave in production code

### Binary Search Debugging

Use case: Bug somewhere in a wide range
Method:
  - Place checkpoint at midpoint
  - Determine normal/abnormal
  - Narrow to problematic half

### Rubber Duck Debugging

Use case: Logic errors, assumptions
Method:
  - Explain code out loud
  - Explain purpose of each line
  - Notice contradictions

### Differential Debugging

Use case: Code that used to work
Method:
  - Compare with working version
  - Identify differences
  - Verify changes one by one

---

## Common Bug Patterns

| Pattern | Symptom | Investigation point |
|---------|---------|---------------------|
| Off-by-one | Fails at boundary | Loop conditions, array indices |
| Null/Undefined | Unexpected crash | Initialization, return value checks |
| Race condition | Intermittent failure | Concurrent access, timing |
| State mutation | Unexpected values | Shared state, side effects |
| Type coercion | Invalid comparison | Implicit type conversion |
| Resource leak | Memory/connection exhaustion | Missing close, reference retention |

---

## Logging Guidelines

### Log Levels

| Level | Use case | Example |
|-------|----------|---------|
| ERROR | Unrecoverable error | Exception, failure |
| WARN | Recoverable but notable | Retry, fallback |
| INFO | Important event | Start/end, state change |
| DEBUG | Detailed diagnostic | Variable values, flow trace |

### Structured Logging

Required fields:
  - timestamp
  - level
  - message
  - context (request_id, user_id, etc.)

Prohibited fields:
  - Passwords, tokens
  - PII (mask if needed)

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

| Pattern | Problem | Alternative |
|---------|---------|-------------|
| Shotgun debugging | Multiple guessing fixes | Verify one at a time |
| Print-and-pray | Random log additions | Place logs based on hypothesis |
| Fixing symptoms | Root cause unresolved | Dig until cause found |
| Ignoring warnings | Missing problem signs | Investigate warnings seriously |
| Debugging in production | High risk | Prioritize local reproduction |

---

## Related

- `skills/data-driven.md` - metrics-driven debugging
- `skills/error-handling.md` - error classification
- `skills/testing.md` - regression testing
