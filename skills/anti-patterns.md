# AI Anti-Patterns

Patterns that AI agents tend to fall into that lead to poor outcomes.

This skill documents common failure patterns observed in AI-driven development,
along with successful alternatives.

---

## Failure patterns

### 1. Configuration-only fixes

- Pattern: Solving problems by changing configuration only
- Problem: Root cause remains unaddressed
- Example: "Increase timeout to fix slow query" -> query stays slow
- Fix: Address root cause (optimize query, add index)

### 2. Post-processing corrections

- Pattern: Fixing symptoms at the end of a pipeline
- Problem: Breaks down in other contexts
- Example: Pixel adjustment after layout -> breaks on different screens
- Fix: Fix at the source (correct calculation in layout)

### 3. Complex conditionals

- Pattern: Building complex if-else chains
- Problem: Combinatorial explosion of bugs
- Example: 10 nested conditions -> impossible to test all paths
- Fix: Simplify logic, use state machines, apply design patterns

### 4. Batch fixes without verification

- Pattern: Fixing multiple issues at once
- Problem: Cannot identify which change caused a problem
- Example: "Fixed 10 files" -> tests fail, unclear which broke
- Fix: Single-step loop: one fix -> verify -> next

### 5. Site-specific hacks

- Pattern: Special-casing for specific inputs
- Problem: Unmaintainable, breaks on new inputs
- Example: `if (host == "example.com") { ... }`
- Fix: Generic solution that handles the class of inputs

### 6. Speculative features

- Pattern: Implementing features not in requirements
- Problem: Scope creep, wasted effort, maintenance burden
- Example: Adding "nice to have" features without approval
- Fix: Strict adherence to PRD/Epic, ask when uncertain

### 7. Evidence-free reporting

- Pattern: Claiming "fixed" or "improved" without proof
- Problem: Unverifiable, potentially incorrect
- Example: "Performance improved" with no numbers
- Fix: Before/After evidence, test results, logs

---

## Success patterns

### 1. Pipeline discipline

- Pattern: Respecting processing stages
- Why it works: Clear responsibilities at each stage
- Example: parse -> validate -> transform -> output
- Key: Do not skip stages, do not backtrack

### 2. Early validation

- Pattern: Validating inputs at boundaries
- Why it works: Easier to fix at source than downstream
- Example: Validate request before processing
- Key: Fail fast with clear error messages

### 3. Single-step verification

- Pattern: One change, immediate verification
- Why it works: Clear cause-effect relationship
- Example: Change one file -> run tests -> next
- Key: Never batch unrelated changes

### 4. Observable boundaries

- Pattern: Logging at stage boundaries
- Why it works: Can trace data flow
- Example: Log input/output at each transformation
- Key: Structured logs with context

### 5. Generic solutions

- Pattern: Solving the general case
- Why it works: Handles future inputs
- Example: Parser that handles all valid inputs
- Key: No special-casing, no magic numbers

---

## Checklist

Before implementing:
- [ ] Not a configuration-only fix
- [ ] Not a post-processing correction
- [ ] Not a complex conditional chain
- [ ] Not a batch of unrelated changes
- [ ] Not a site-specific hack
- [ ] Not a speculative feature

During implementation:
- [ ] Following pipeline discipline
- [ ] Validating early
- [ ] Verifying each change
- [ ] Logging at boundaries
- [ ] Building generic solutions

---

## Related

- `AGENTS.md` - Non-negotiables section
- `.agent/rules/impl-gate.md` - development loop
- `.agent/rules/dod.md` - evidence requirements
