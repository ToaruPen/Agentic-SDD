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
/create-prd -> /create-epic -> /create-issues -> /impl -> /review-cycle -> /review
     |            |              |              |             |            |
     v            v              v              v             v            v
  7 questions   3-layer guard  LOC-based      Full estimate  Local loop   DoD gate
  + checklist   + 3 required   50-300 LOC     + confidence   review.json  + sync-docs
```

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

```
/impl [issue-number]
```

Create a Full estimate (11 sections) before implementation.

### 4.5) Local review cycle (required)

```
/review-cycle [scope-id]
```

Generate `review.json` during development and iterate (fix -> re-review).

If you set `GH_ISSUE=123`, it reads the Issue body and `- PRD:` / `- Epic:` references
to assemble SoT automatically.

### 5) Review

```
/review
```

Run the DoD check and `/sync-docs`.

---

## Directory Structure

```
.agent/
├── commands/           # command definitions
│   ├── create-prd.md
│   ├── create-epic.md
│   ├── create-issues.md
│   ├── impl.md
│   ├── review-cycle.md
│   ├── review.md
│   ├── sync-docs.md
│   └── worktree.md
├── schemas/            # JSON schema
│   └── review.json
├── rules/              # rule definitions
│   ├── docs-sync.md
│   ├── dod.md
│   ├── epic.md
│   └── issue.md
└── agents/
    └── reviewer.md

docs/
├── prd/
│   └── _template.md    # PRD template (Japanese output)
├── epics/
│   └── _template.md    # Epic template (Japanese output)
├── decisions.md        # ADR log
└── glossary.md         # glossary

skills/                 # design skills
├── estimation.md
└── worktree-parallel.md

scripts/
├── agentic-sdd
├── install-agentic-sdd.sh
├── assemble-sot.py
├── extract-issue-files.py
├── review-cycle.sh
├── setup-global-agentic-sdd.sh
├── sync-agent-config.sh
├── test-review-cycle.sh
├── test-worktree.sh
├── validate-review-json.py
└── worktree.sh

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
- `agents/` - subagents like `@sdd-reviewer`
- `skills/` - `sdd-*` / `tdd-*` skills (load via the `skill` tool)

##### (Optional) Global `/agentic-sdd` command

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
