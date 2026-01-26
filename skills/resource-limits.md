# Resource Limits

Optional skill for large-scale projects where runaway processes can cause problems.

This skill covers safeguards against AI agent runaway behavior.

---

## When to use

- Large codebases (100k+ LOC)
- Resource-intensive builds (Rust, C++, large monorepos)
- Long-running test suites
- Environments where runaway processes can cause damage

## When not to use

- Small projects with fast builds/tests
- Environments with built-in resource controls
- Quick prototyping

---

## Core principle

> Assume anything can malfunction: infinite loops, memory explosion,
> deadlocks, processes ignoring signals.
> This is operational reality, not paranoia.

---

## Required limits

### Time limits

Always use timeouts with SIGKILL fallback:

- Normal build/test: `timeout -k 10 600` (10 min)
- Single focused test: `timeout -k 10 120` (2 min)
- Full harness run: `timeout -k 10 900` (15 min)

Why `-k` is required:
- SIGTERM can be ignored by misbehaving processes
- SIGKILL ensures termination after grace period

### Scope limits

Limit the scope of operations:

- Tests: Avoid `npm test` (all) -> Prefer `npm test -- --filter=<name>`
- Build: Avoid `cargo build --all` -> Prefer `cargo build -p <crate>`
- Lint: Avoid `eslint .` -> Prefer `eslint src/changed/**`

### Memory limits

For known memory-intensive operations:

- Use OS-level limits: `prlimit`, `ulimit`, `cgroups`
- Monitor memory usage during long operations
- Clean up build artifacts periodically

### Disk limits

- Periodically clean build directories (`target/`, `node_modules/.cache/`)
- Monitor disk usage in CI environments
- Set up alerts for disk space

---

## Prohibited operations

Operations that should never run without limits:

- Unscoped test suite: Compiles hundreds of binaries, exhausts RAM
- `--all-targets` builds: Memory explosion
- Recursive operations at root: Affects entire filesystem
- Long-running processes without timeout: Hangs forever

---

## Safe patterns

### Running tests

```bash
# Bad: no timeout, no scope
cargo test

# Good: timeout with SIGKILL fallback, scoped to library
timeout -k 10 600 cargo test -p my-crate --lib
```

### Running builds

```bash
# Bad: all targets
cargo build --all-targets

# Good: specific package, release profile
timeout -k 10 600 cargo build -p my-crate --release
```

### Running linters

```bash
# Bad: entire codebase
eslint .

# Good: changed files only
eslint $(git diff --name-only HEAD~1 -- '*.ts' '*.tsx')
```

---

## Escape conditions

When encountering resource issues:

1. Stop the operation immediately
2. Report the issue with specifics (what, where, how much)
3. Propose a scoped alternative
4. Wait for human approval before retrying

---

## Checklist

Before running operations:
- [ ] Timeout with SIGKILL fallback set
- [ ] Scope limited to necessary targets
- [ ] Memory-intensive operations identified
- [ ] Disk cleanup scheduled if needed

If operation exceeds limits:
- [ ] Stopped immediately
- [ ] Issue reported with specifics
- [ ] Scoped alternative proposed
- [ ] Human approval obtained

---

## Related

- `AGENTS.md` - Non-negotiables section
- `.agent/rules/impl-gate.md` - quality gate
- `skills/anti-patterns.md` - failure patterns
