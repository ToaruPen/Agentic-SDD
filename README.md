# Agentic-SDD

A workflow template to help non-engineers run AI-driven development while preventing LLM overreach.

Agentic-SDD = Agentic Spec-Driven Development

Note: User-facing interactions and generated artifacts (PRDs/Epics/Issues) remain in Japanese.

---

## Concept

- Decide requirements/specs until the implementation is largely determined
- Prevent overreach and push toward simpler designs
- Use a consistent flow: PRD -> Epic -> Issues -> Implementation -> Review

---

## Workflow

```
/agentic-sdd* -> /create-prd -> /create-epic -> /generate-project-config** -> /create-issues -> /estimation -> /impl|/tdd -> /review-cycle -> /review -> /create-pr
     |            |              |              |                            |              |            |              |            |
     v            v              v              v                            v              v            v              v            v
     Install       7 questions    3-layer guard  Generate project            LOC-based       Full estimate Implement      Local loop    DoD gate       Push + PR create
                  + checklist    + 3 required   skills/rules                50-300 LOC      + approval    + tests        review.json   + sync-docs    (gh)
```

\*\* Optional: generates project-specific skills/rules based on Epic tech stack and Q6 requirements.

\* One-time install of Agentic-SDD workflow files in the repo.
Optional: enable GitHub-hosted CI (GitHub Actions) via `/agentic-sdd --ci github-actions` and enforce it with branch protection.

---

## Parallel Implementation (git worktree)

Agentic-SDD supports deterministic parallel implementation by running one Issue per branch/worktree.

Guardrails:

- Each Issue must declare `### 変更対象ファイル（推定）` (used as the conflict-check input)
- Only mark Issues as `parallel-ok` when declared file sets are disjoint

Helper script:

Note: `worktree.sh new` uses `gh issue develop` to create a linked branch on the Issue as the
"in progress" source of truth. It fails fast if the Issue already has linked branches.

```bash
# Detect overlaps before starting
./scripts/worktree.sh check --issue 123 --issue 124

# Create a worktree per Issue
./scripts/worktree.sh new --issue 123 --desc "add user profile" --tool opencode
./scripts/worktree.sh new --issue 124 --desc "add settings page" --tool opencode
```

Note: worktrees share the same `.git` database. Merge incrementally (finish one, merge one) to reduce conflicts.

---

## Quick Start

### 0) Install (one-time per repo)

If Agentic-SDD is not installed in your repository yet, install it first:

```
/agentic-sdd opencode minimal
```

Optional (opt-in): install a GitHub Actions CI template (tests + lint + typecheck):

```
/agentic-sdd --ci github-actions opencode minimal
```

After install, edit `.github/workflows/agentic-sdd-ci.yml` and set the 3 env vars to your project's commands.
To enforce in GitHub, require the check `agentic-sdd-ci / ci` via branch protection rules.

If you do not have `/agentic-sdd` yet, set it up once by cloning this repo and running:

```bash
./scripts/setup-global-agentic-sdd.sh
```

Use `full` instead of `minimal` if you want GitHub issue/PR templates.

After installation, OpenCode exposes Agentic-SDD's init checklist as `/sdd-init` (because `/init` is built-in).

### 1) Create a PRD

```
/create-prd [project-name]
```

Answer 7 questions to create a PRD. Q6 is choice-based; at least one negative/abnormal AC is required.

### 2) Create an Epic

```
/create-epic [prd-file]
```

Create a technical plan and an Issue split proposal. Three lists are required:
external services / components / new tech.

### 3) Create Issues

```
/create-issues [epic-file]
```

Create Issues following the granularity rules (50-300 LOC).

### 4) Implement

Create an estimate (required before implementation):

```
/estimation [issue-number]
```

```
/impl [issue-number]
```

`/impl` is the normal implementation flow. `/tdd` is the strict TDD flow.

To run strict TDD directly:

```
/tdd [issue-number]
```

Both `/impl` and `/tdd` require the same Full estimate + user approval gate (via `/estimation`).

### 5) Review (`/review` (`/review-cycle`))

Final gate:

```
/review
```

Run the DoD check and `/sync-docs`.

During development (and before committing, per `/impl`), iterate locally with:

```
/review-cycle [scope-id]
```

`/review-cycle` generates `review.json` and is meant to be used in a fix -> re-review loop.

If you set `GH_ISSUE=123`, it reads the Issue body and `- PRD:` / `- Epic:` references
to assemble SoT automatically.

### 6) Create PR

After `/review` is approved, push the branch and create a PR:

```
/create-pr [issue-number]
```

If you enable CI (optional), wait for CI checks and fix failures before merging.

---

## Directory Structure

```
.agent/
├── commands/           # command definitions
│   ├── create-prd.md
│   ├── create-epic.md
│   ├── generate-project-config.md
│   ├── create-issues.md
│   ├── create-pr.md
│   ├── estimation.md
│   ├── impl.md
│   ├── tdd.md
│   ├── review-cycle.md
│   ├── review.md
│   ├── sync-docs.md
│   └── worktree.md
├── schemas/            # JSON schema
│   └── review.json
├── rules/              # rule definitions
│   ├── availability.md
│   ├── branch.md
│   ├── commit.md
│   ├── datetime.md
│   ├── docs-sync.md
│   ├── dod.md
│   ├── epic.md
│   ├── impl-gate.md
│   ├── issue.md
│   ├── observability.md
│   ├── performance.md
│   └── security.md
└── agents/
    ├── docs.md
    └── reviewer.md

docs/
├── prd/
│   └── _template.md    # PRD template (Japanese output)
├── epics/
│   └── _template.md    # Epic template (Japanese output)
├── decisions.md        # ADR log
└── glossary.md         # glossary

skills/                 # design skills
├── README.md
├── anti-patterns.md
├── api-endpoint.md
├── class-design.md
├── crud-screen.md
├── data-driven.md
├── debugging.md
├── error-handling.md
├── estimation.md
├── resource-limits.md
├── security.md
├── testing.md
├── tdd-protocol.md
└── worktree-parallel.md

scripts/
├── agentic-sdd
├── assemble-sot.py
├── bench-sdd-docs.py
├── create-pr.sh
├── extract-epic-config.py
├── extract-issue-files.py
├── generate-project-config.py
├── install-agentic-sdd.sh
├── resolve-sync-docs-inputs.py
├── review-cycle.sh
├── setup-global-agentic-sdd.sh
├── sot_refs.py
├── sync-agent-config.sh
├── validate-review-json.py
└── worktree.sh

templates/
└── project-config/     # templates for /generate-project-config
    ├── config.json.j2
    ├── rules/
    │   ├── api-conventions.md.j2
    │   ├── performance.md.j2
    │   └── security.md.j2
    └── skills/
        └── tech-stack.md.j2

AGENTS.md               # AI agent rules
```

---

## Key Rules (Overview)

### PRD completion

- 7-question format (Q6 is choice-based)
- Completion checklist (10 items)
- Banned vague words dictionary (avoid ambiguity)
- At least one negative/abnormal AC

### Epic overreach guardrails

- 3-layer structure (PRD constraints -> AI rules -> review checklist)
- Counting definitions (external services / components / new tech)
- Allow/deny list per technical policy
- Required artifacts (3 lists)

### Issue granularity

- LOC: 50-300
- Files: 1-5
- AC: 2-5
- Exception labels require required fields

### Estimation

- Full estimate required (11 sections)
- Confidence levels (High/Med/Low)
- Always write `N/A (reason)` when not applicable

### Source-of-truth rules

- PRD -> Epic -> Implementation priority
- `/sync-docs` output requires references

---

## Design Spec

See `DESIGN.md` for the full design.

---

## Supported AI Tools

- Claude Code
- OpenCode
- Codex CLI

`.agent/` is the source of truth. Tool-specific configs can be generated via the sync script.

### Tool setup

#### Claude Code

It reads `AGENTS.md` automatically.

```bash
# Run at the project root
claude
```

#### OpenCode

Run the sync script to generate OpenCode configs.

Note: OpenCode has a built-in `/init` (generates AGENTS.md), so Agentic-SDD's init is exposed as `/sdd-init`.

```bash
# 1) Sync
./scripts/sync-agent-config.sh opencode

# 2) Start OpenCode
opencode
```

Generated under `.opencode/` (gitignored):

- `commands/` - custom commands like `/create-prd`
- `agents/` - subagents like `@sdd-reviewer`, `@sdd-docs`
- `skills/` - `sdd-*` / `tdd-*` skills (load via the `skill` tool)

##### Global `/agentic-sdd` command

This repo provides global definitions (OpenCode/Codex/Claude/Clawdbot) and a helper CLI `agentic-sdd`
to install Agentic-SDD into new projects.

Setup:

```bash
# Clone this repo and run at the repo root
./scripts/setup-global-agentic-sdd.sh
```

Existing files are backed up as `.bak.<timestamp>` before overwrite.

After setup, run `/agentic-sdd` in each tool.

#### Codex CLI

Run the sync script to generate Codex CLI configs.

```bash
# 1) Sync
./scripts/sync-agent-config.sh codex

# 2) Start Codex CLI
codex
```

### Source-of-truth and sync

```
.agent/          <- source of truth (edit here)
    |
    +---> .opencode/  <- for OpenCode (generated, gitignored)
    +---> .codex/     <- for Codex CLI (generated, gitignored)
```

If you edit files under `.agent/`, re-run the sync script.

```bash
# Sync for all tools
./scripts/sync-agent-config.sh all

# Preview (no changes)
./scripts/sync-agent-config.sh --dry-run
```

### Estimate approval gate enforcement (recommended)

To prevent accidental implementation before the `/estimation` approval gate (mode selection + explicit user approval), Agentic-SDD can enforce a local "approval pass":

- Git hooks (tool-agnostic final defense): `.githooks/pre-commit`, `.githooks/pre-push`
  - Enable: `./scripts/setup-githooks.sh` (the installer attempts to configure this automatically)
- Claude Code: `.claude/settings.json` (PreToolUse hooks: Edit/Write + git commit/push)
- OpenCode: `.opencode/plugins/agentic-sdd-gate.js` (generated by `./scripts/sync-agent-config.sh opencode`)

Approvals are stored locally (gitignored) under:

- `.agentic-sdd/approvals/issue-<n>/estimate.md`
- `.agentic-sdd/approvals/issue-<n>/approval.json` (hash-bound to `estimate.md`)

After Phase 2.5 is approved, create the record:

```bash
python3 scripts/create-approval.py --issue <n> --mode <impl|tdd|custom>
python3 scripts/validate-approval.py
```

---

## First-cycle Guide

### Pick a topic

- Recommended: single feature, not too small
- Avoid: many external integrations, auth, large refactors

### Suggested defaults

| Item | Default |
|------|---------|
| Estimation | Full required |
| Exception labels | Do not use |
| Technical policy | Simple-first |
| Q6 Unknowns | Aim for 0 |

### Success criteria

- PRD passes all completion checklist items
- Epic contains all three required lists
- Issues fit granularity rules
- Estimates are Full (11 sections)
- `/sync-docs` yields "no diff"
- PR gets merged

---

## License

MIT
