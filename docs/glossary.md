# Glossary

Definitions of terms used in this repository and in the Agentic-SDD workflow.

---

## Agentic-SDD Terms

- PRD: Product Requirements Document. A requirements doc created via 7 questions.
- Epic: Implementation plan derived from a PRD (includes technical design and Issue splitting).
- AC: Acceptance Criteria. Must be observable/testable.
- DoD: Definition of Done. Criteria for considering an Issue/PR complete.
- sync-docs: Command/process to verify consistency across PRD/Epic/implementation.
- SoT: Source of Truth.
- worktree: Git feature to create multiple working trees sharing one repo (.git).

---

## Technical Policy

- シンプル優先 (Simple-first): Max 1 external service, max 3 new libraries, microservices forbidden.
- バランス (Balanced): Max 3 external services, max 5 new libraries, async infra allowed with explicit reason.
- 拡張性優先 (Extensibility-first): No hard limits, but every choice requires a reason.

---

## Counting Definitions

- External services
  - Definition: separately managed services used over the network
  - Counting unit: each SaaS / managed DB / identity provider / external API counts as 1
- Components
  - Definition: deployable unit
  - Counting unit: each separate process / job / worker / batch counts as 1
- New tech
  - Definition: major technology category newly introduced
  - Counting unit: each DB / queue / auth / observability / framework / cloud service counts as 1

---

## Progress Counting Criteria

### Changes that count (direct contribution to main goal)

- New feature (with regression test)
- Bug fix (with regression test)
- Stability improvement (crash elimination + test)
- Meaningful test coverage addition

### Changes that do not count (drift prevention)

- Tool improvement only (if not immediately used)
- Performance optimization only (if not a bottleneck)
- Documentation cleanup only (if not a blocker)
- Refactoring only (if no test added)

### Drift warning

If non-counting changes continue consecutively, stop and ask:
"Is this contributing to the main goal? Which PRD/Epic requirement does this address?"

---

## Issue Terms

- Granularity rules: target size for a single Issue (50-300 LOC, 1-5 files, 2-5 AC).
- Exception labels: labels used when violating granularity rules (required fields: reason / impact / risk).
- blocked: label indicating the Issue is blocked by another Issue.
- parallel-ok: label indicating work can proceed in parallel.

---

## Git Terms

- git worktree: multiple working directories for one repository
- conflict guard: deterministic check that parallel Issues do not overlap in declared change-target files

---

## Estimation Terms

- Full estimate: 11-section estimation format (required in this repo).
- Confidence: High / Med / Low.
- Range: estimate ranges such as 2-4h, 50-100 LOC.

---

## PRD Banned Vague Words

- Banned vague words: ambiguous expressions that must not be used in PRDs (see `docs/prd/_template.md`).
  Examples: "適切に", "なるべく", "高速".
- Rewrite: replace vague words with measurable conditions (numbers, thresholds, concrete rules).

---

## Project-specific Terms

Add project-specific terms here.

- [term-1]: [definition]
- [term-2]: [definition]
