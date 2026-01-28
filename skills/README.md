# Skills

Design skills: patterns and checklists to consult during implementation.

These docs are language/framework-agnostic and concept-based.

---

## Skill list

### Core Skills

- [security.md](./security.md): security design (threat modeling/secure coding/OWASP)
- [debugging.md](./debugging.md): debugging strategies (systematic approach/common patterns)
- [class-design.md](./class-design.md): class/module design (SOLID/patterns/cohesion)
- [testing.md](./testing.md): testing strategy/types/coverage
- [tdd-protocol.md](./tdd-protocol.md): TDD execution protocol (Red/Green/Refactor)
- [error-handling.md](./error-handling.md): error handling (classification/processing/UX/logging)

### Implementation Skills

- [api-endpoint.md](./api-endpoint.md): REST API endpoint design
- [crud-screen.md](./crud-screen.md): CRUD screen design
- [estimation.md](./estimation.md): estimation (create a Full estimate before implementation)

### Process Skills

- [worktree-parallel.md](./worktree-parallel.md): parallel implementation with git worktree (deterministic guardrails)
- [anti-patterns.md](./anti-patterns.md): AI anti-patterns and safer alternatives
- [data-driven.md](./data-driven.md): data-driven development (metrics and evidence)
- [resource-limits.md](./resource-limits.md): resource limits to prevent runaway processes

---

## How to use

### 1) Consult before implementation

```
Before running /impl #123, check relevant skills:

- Designing classes/modules -> class-design.md
- Security requirements -> security.md
- Implementing an API -> api-endpoint.md
- Implementing a screen -> crud-screen.md
- Designing error handling -> error-handling.md
- Debugging issues -> debugging.md
```

### 2) Use as a checklist

Each skill contains a checklist. Use it when you finish implementation.

### 3) Use for reviews

Use skill checklists as review focus areas.

---

## Skill structure

Each skill file follows this structure:

```markdown
# Skill name

## Overview
[scope]

## Principles
[guiding principles]

## Patterns
[concrete patterns]

## Checklist
[items to verify]

## Anti-patterns
[things to avoid]

## Related
[other files to consult]
```

---

## Adding project-specific skills

1. Add a new `.md` file under `skills/`
2. Follow the structure above
3. Add it to this README

Examples:

- `skills/authentication.md` - authentication flows
- `skills/file-upload.md` - file uploads
- `skills/batch-processing.md` - batch processing

---

## Related

- `.agent/commands/impl.md` - implementation command
- `.agent/rules/dod.md` - Definition of Done
- `docs/decisions.md` - engineering decisions
