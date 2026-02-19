# AGENTS.md

Rules for AI agents working in this repository.

Note: User-facing interactions and generated artifacts (PRDs/Epics/Issues/PRs) remain in Japanese.
This control documentation is written in English to reduce token usage during agent bootstrap.

## Start Here (Development Cycle Protocol)

Minimal protocol for a first-time agent to decide the next action.

```text
Invariant (SoT)
- Priority order: PRD (requirements) > Epic (implementation plan) > Implementation (code)
- If you detect a contradiction, STOP and ask a human with references (PRD/Epic/code:line).
  Do not invent requirements.

Fail-fast (no fallback in implementation)
- During implementation, do not add "fallback" behavior that silently changes outcomes.
  If a required input/assumption is missing or ambiguous, fail fast with an explicit error,
  and ask a human (with PRD/Epic/code references) instead of guessing.
- Backward-compat shims or fallback paths are allowed only when they are behavior-preserving,
  do not hide errors, and add no cyclomatic complexity.

Agent Guidelines (simplicity-first)
- Always prefer simplicity over pathological correctness.
- YAGNI, KISS, DRY.
- Prefer explicit failure over compatibility shims when requirements or inputs are missing.

Questions (user interaction)
- When you need to ask the user a question, you MUST use the QuestionTool (the `question` tool).
  Do not ask questions in free-form text.

Static analysis (required)
- You must introduce and keep running static analysis: lint, format, and typecheck.
- If the repository has no lint/format/typecheck yet, treat it as a blocker and introduce the minimal viable checks before proceeding.
- If you cannot introduce or run a required check due to environment or constraints, STOP and ask a human for an explicit exception (with rationale and impact).

Release hygiene (required)
- After making changes to this repo, you MUST update `CHANGELOG.md`, publish a GitHub Release (tag),
  and update pinned scripts (e.g. `scripts/agentic-sdd` default ref).

0) Bootstrap
- Read AGENTS.md (this section + command list). Read README.md only if needed (Workflow section).
- Read `.agent/commands/`, `.agent/rules/`, and `skills/` on-demand for the next command only.

1) Entry decision (where to start)

For new development:
- No PRD: /create-prd
- PRD exists but no Epic: /create-epic
- Epic exists but no Issues / not split: /create-issues
- Issues exist: ask the user to choose /impl vs /tdd (do not choose on your own)
  - Then run: /impl <issue-id> or /tdd <issue-id>

For bug fix / refactoring:
- Small (1-2 Issues): Create Issue directly -> /impl or /tdd
- Medium (3-5 Issues): /create-epic (reference existing PRD) -> /create-issues
- Large (6+ Issues): /create-prd -> /create-epic -> /create-issues

Note: Even for direct Issue creation, include PRD/Epic links for traceability.
Bug fix Issues require Priority (P0-P4). See `.agent/rules/issue.md` for details.

2) Complete one Issue (iterate)
- /impl or /tdd: pass the implementation gates (.agent/rules/impl-gate.md)
  - Full estimate (11 sections) -> user approval -> implement -> add/run tests
  - Worktree is required for Issue branches (see `.agent/rules/impl-gate.md` Gate -1)
- /review-cycle: run locally before committing (fix -> re-run)
- /final-review: always run /sync-docs; if there is a diff, follow SoT and re-check

3) PR / merge
- Create a PR only after /final-review passes (do not change anything outside the Issue scope)
  - Then run: /create-pr
```

### Parallel work (git worktree)

When using `git worktree` to implement multiple Issues in parallel:

- One Issue = one branch = one worktree (never mix changes)
- If multiple related Issues overlap heavily, create a single "parent" Issue as the implementation unit and keep the related Issues as tracking-only children (no branches/worktrees for children).
- Do not edit PRD/Epic across parallel branches; serialize SoT changes
- Apply `parallel-ok` only when declared change-target file sets are disjoint (validate via `./scripts/worktree.sh check`)

---

## Non-negotiables

<non_negotiables>
Absolute prohibitions with no exceptions:

1. **No case-specific hacks**
   - Do not write conditional branches like `if (hostname == "xxx")`
   - Do not use magic numbers for adjustments

2. **No speculative requirements**
   - Do not implement features not documented in PRD/Epic
   - When uncertain, ask human (follow SoT priority order)

3. **No evidence-free completion reports**
   - Reporting only "Fixed" or "Improved" is not acceptable
   - Required: Before/After diff, test results, or logs as evidence

4. **No batch changes**
   - Do not mix unrelated changes in one commit
   - Follow single-step loop: one fix -> verify -> next

5. **No invalid tests**
   - Failure reproducibility: Test must fail before the change
   - Correction assurance: Test must pass after the change
   - Without both conditions, the test is not valid evidence
     </non_negotiables>

---

## Project Overview

Agentic-SDD (Agentic Spec-Driven Development)

A workflow template to help non-engineers run AI-driven development while preventing LLM overreach.

---

## Key Files

- `.agent/commands/`: command definitions (create-prd, create-epic, generate-project-config, ...)
- `.agent/rules/`: rule definitions (docs-sync, dod, epic, issue, security, performance, ...)
- `docs/prd/_template.md`: PRD template (Japanese output)
- `docs/epics/_template.md`: Epic template (Japanese output)
- `docs/glossary.md`: glossary
- `templates/project-config/`: templates for `/generate-project-config`

---

## Commands

- `/init`: initialize the Agentic-SDD checklist (OpenCode alias: `/sdd-init`)
- `/create-prd`: create a PRD (7 questions)
- `/research`: create reusable research artifacts for PRD/Epic/estimation
- `/create-epic`: create an Epic (requires 3 lists: external services / components / new tech)
- `/generate-project-config`: generate project-specific skills/rules from Epic
- `/create-issues`: create Issues (granularity rules)
- `/debug`: create a structured debugging/investigation note (Issue comment or a new Investigation Issue)
- `/estimation`: create a Full estimate (11 sections) and get approval
- `/impl`: implement an Issue (Full estimate required)
- `/tdd`: implement via TDD (Red -> Green -> Refactor)
- `/ui-iterate`: iterate UI redesign in short loops (capture -> patch -> verify)
- `/test-review`: run fail-fast test review checks before review/PR gates
- `/review-cycle`: local review loop (codex exec -> review.json)
- `/final-review`: review (DoD check)
- `/create-pr`: push branch and create a PR (gh)
- `/codex-pr-review`: request a Codex bot review on a PR and iterate until feedback is resolved
- `/sync-docs`: consistency check between PRD/Epic/code
- `/worktree`: manage git worktrees for parallel Issues
- `/cleanup`: clean up worktree and local branch after merge

---

## Rules (read on-demand)

To keep this bootstrap file small, detailed rules live in these files:

- PRD: `.agent/commands/create-prd.md`, `docs/prd/_template.md`
- Epic: `.agent/commands/create-epic.md`, `.agent/rules/epic.md`
- Project Config: `.agent/commands/generate-project-config.md`, `templates/project-config/`
- Issues: `.agent/commands/create-issues.md`, `.agent/rules/issue.md`
- Estimation: `.agent/commands/estimation.md`, `.agent/rules/impl-gate.md`
- Review: `.agent/commands/final-review.md`, `.agent/rules/dod.md`, `.agent/rules/docs-sync.md`
- Production Quality: `.agent/rules/security.md`, `.agent/rules/performance.md`, `.agent/rules/observability.md`, `.agent/rules/availability.md`

---

## References

- Glossary: `docs/glossary.md`
- Decisions index: `docs/decisions.md`
- Decisions body rules: `docs/decisions/README.md`
