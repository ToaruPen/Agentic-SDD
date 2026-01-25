# AGENTS.md

Rules for AI agents working in this repository.

Note: User-facing interactions and generated artifacts (PRDs/Epics/Issues) remain in Japanese.
This control documentation is written in English to reduce token usage during agent bootstrap.

## Start Here (Development Cycle Protocol)

Minimal protocol for a first-time agent to decide the next action.

```text
Invariant (SoT)
- Priority order: PRD (requirements) > Epic (implementation plan) > Implementation (code)
- If you detect a contradiction, STOP and ask a human with references (PRD/Epic/code:line).
  Do not invent requirements.

Release hygiene (required)
- After making changes to this repo, you MUST update `CHANGELOG.md`, publish a GitHub Release (tag),
  and update pinned scripts (e.g. `scripts/agentic-sdd` default ref).

0) Bootstrap
- Read AGENTS.md (this section + command list). Read README.md only if needed (Workflow section).
- Read `.agent/commands/`, `.agent/rules/`, and `skills/` on-demand for the next command only.

1) Entry decision (where to start)
- No PRD: /create-prd
- PRD exists but no Epic: /create-epic
- Epic exists but no Issues / not split: /create-issues
- Issues exist: ask the user to choose /impl vs /tdd (do not choose on your own)
  - Then run: /impl <issue-id> or /tdd <issue-id>

2) Complete one Issue (iterate)
- /impl or /tdd: pass the implementation gates (.agent/rules/impl-gate.md)
  - Full estimate (11 sections) -> user approval -> implement -> add/run tests
- /review-cycle: run locally before committing (fix -> re-run)
- /review: always run /sync-docs; if there is a diff, follow SoT and re-check

3) PR / merge
- Create a PR only after /review passes (do not change anything outside the Issue scope)
  - Then run: /create-pr
```

### Parallel work (git worktree)

When using `git worktree` to implement multiple Issues in parallel:

- One Issue = one branch = one worktree (never mix changes)
- Do not edit PRD/Epic across parallel branches; serialize SoT changes
- Apply `parallel-ok` only when declared change-target file sets are disjoint (validate via `./scripts/worktree.sh check`)

---

## Project Overview

Agentic-SDD (Agentic Spec-Driven Development)

A workflow template to help non-engineers run AI-driven development while preventing LLM overreach.

---

## Key Files

- `.agent/commands/`: command definitions (create-prd, create-epic, ...)
- `.agent/rules/`: rule definitions (docs-sync, dod, epic, issue, ...)
- `docs/prd/_template.md`: PRD template (Japanese output)
- `docs/epics/_template.md`: Epic template (Japanese output)
- `docs/glossary.md`: glossary

---

## Commands

- `/create-prd`: create a PRD (7 questions)
- `/create-epic`: create an Epic (requires 3 lists: external services / components / new tech)
- `/create-issues`: create Issues (granularity rules)
- `/estimation`: create a Full estimate (11 sections) and get approval
- `/impl`: implement an Issue (Full estimate required)
- `/tdd`: implement via TDD (Red -> Green -> Refactor)
- `/review-cycle`: local review loop (codex exec -> review.json)
- `/review`: review (DoD check)
- `/create-pr`: push branch and create a PR (gh)
- `/sync-docs`: consistency check between PRD/Epic/code
- `/worktree`: manage git worktrees for parallel Issues

---

## Rules (read on-demand)

To keep this bootstrap file small, detailed rules live in these files:

- PRD: `.agent/commands/create-prd.md`, `docs/prd/_template.md`
- Epic: `.agent/commands/create-epic.md`, `.agent/rules/epic.md`
- Issues: `.agent/commands/create-issues.md`, `.agent/rules/issue.md`
- Estimation: `.agent/commands/estimation.md`, `.agent/rules/impl-gate.md`
- Review: `.agent/commands/review.md`, `.agent/rules/dod.md`, `.agent/rules/docs-sync.md`

---

## References

- Glossary: `docs/glossary.md`
- Decisions: `docs/decisions.md`
