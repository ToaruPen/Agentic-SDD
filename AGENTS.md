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

## Mandatory Rules

### 1) When creating a PRD

- Use the 7-question format
- Q6 (technical constraints) is choice-based
- Check banned vague words (see PRD template)
- Include at least one negative/abnormal AC
- If there are 2+ Unknown items, the PRD is not considered complete

### 2) When creating an Epic

- Always include the 3 required lists (external services / components / new tech)
- Apply the constraints per technical policy
- Always present simpler alternatives when available
- Do not add complexity "for future extensibility" only

### 3) When creating Issues

- Granularity: 50-300 LOC, 1-5 files, 2-5 AC
- If using an exception label, fill in all required fields
- Explicitly state dependencies

### 4) When estimating

- Full estimate (11 sections) is mandatory
- For non-applicable sections, write `N/A` with a reason
- Include confidence (High/Med/Low)

### 5) When reviewing

- Run `/sync-docs`
- If there is a diff, provide references (PRD/Epic/code)
- Check the DoD checklist

---

## Prohibited

- Using banned vague words in PRDs (e.g. "適切に", "なるべく", "高速"; see `docs/prd/_template.md`)
- Creating an Epic without the required lists
- Creating Issues that ignore the granularity rules
- Lite estimates (Full is required)
- Reporting diffs without references
- Changing higher-level docs (PRD) without explicit confirmation

---

## Counting Definitions

- External services: count each SaaS / managed DB / identity provider / external API as 1
- Components: count each deployable unit (process/job/worker/batch) as 1
- New tech: count each major category (DB/queue/auth/observability/framework/cloud service) as 1

---

## Constraints by Technical Policy

### Simple-first

- External services: max 1
- New libraries: max 3
- New components: max 3
- Async infrastructure: forbidden
- Microservices: forbidden
- Kubernetes (and similar): forbidden

### Balanced

- External services: max 3
- New libraries: max 5
- New components: max 5
- Async infrastructure: allowed with an explicit reason
- Microservices: allowed with an explicit reason

---

## Source-of-Truth Hierarchy

Priority: PRD (requirements) > Epic (implementation plan) > Implementation (code)

If there is a contradiction, follow the higher-level document.

---

## References

- Glossary: `docs/glossary.md`
- Decisions: `docs/decisions.md`
