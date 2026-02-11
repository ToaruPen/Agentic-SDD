# Agentic-SDD

A workflow template to help non-engineers run AI-driven development while preventing LLM overreach.

Agentic-SDD = Agentic Spec-Driven Development

Note: User-facing interactions and generated artifacts (PRDs/Epics/Issues/PRs) remain in Japanese.

---

## Concept

- Decide requirements/specs until the implementation is largely determined
- Prevent overreach and push toward simpler designs
- Use a consistent flow: PRD -> Epic -> Issues -> Implementation -> Review

---

## Workflow

```
/agentic-sdd* -> /create-prd -> /create-epic -> /generate-project-config** -> /create-issues -> /estimation -> /impl|/tdd -> /ui-iterate*** -> /review-cycle -> /review -> /create-pr -> [Merge] -> /cleanup
     |            |              |              |                            |              |            |              |              |            |            |                         |
     v            v              v              v                            v              v            v              v              v            v            v                         v
     Install       7 questions    3-layer guard  Generate project            LOC-based       Full estimate Implement      UI round loop  Local loop    DoD gate       Push + PR create       Remove worktree
                  + checklist    + 3 required   skills/rules                50-300 LOC      + approval    + tests        capture/verify review.json   + sync-docs    (gh)                   + local branch
```

\*\* Optional: generates project-specific skills/rules based on Epic tech stack and Q6 requirements.

\*\*\* Optional: recommended for iterative UI redesign Issues.

\* One-time install of Agentic-SDD workflow files in the repo.
Optional: enable GitHub-hosted CI (GitHub Actions) via `/agentic-sdd --ci github-actions` and enforce it with branch protection.

---

## External multi-agent harnesses

If you are using an external multi-agent harness, treat it as the **single orchestration layer** (agent lifecycle, task queue, state/progress tracking, parallel execution).

Use Agentic-SDD as the workflow/rules layer (PRD → Epic → Issues → estimation gates → review gates), and tailor your project's `AGENTS.md` and `skills/` to match the harness's operating model.

In other words:

- External harness = orchestration SoT (state/progress)
- Agentic-SDD = spec-driven workflow + quality gates
- Avoid mixing orchestration layers (do not enable `--shogun-ops` in this case)

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

## Shogun Ops: tmux launcher (experimental)

Shogun Ops(auto) can be operated with a deterministic tmux layout.

- Session: `shogun-ops`
- Window: `ops`
- Pane titles: `upper`, `middle`, `ashigaru1`, `ashigaru2`, `ashigaru3`

```bash
# Show the tmux command sequence (no tmux required)
./scripts/shogun-tmux.sh --dry-run init

# Create the session (requires tmux)
./scripts/shogun-tmux.sh init

# Send order-injection command to the middle pane
./scripts/shogun-tmux.sh send-order

# More robust injection (send command and Enter separately)
./scripts/shogun-tmux.sh send-order --send-keys-mode two-step

# Attach
./scripts/shogun-tmux.sh attach
```

Optional: install the tmux shim (opt-in via `--shogun-ops`) and put `scripts/` first in `PATH`
to allow opening the Shogun Ops layout with:

```bash
PATH="$(pwd)/scripts:$PATH" tmux --shogun-ops
```

## Shogun Ops: GitHub sync (experimental)

Sync the local ops status to a GitHub Issue by adding a comment and updating labels.

Notes:

- Intended to be executed by **Middle only** (single writer policy).
- Labels are created/updated automatically: `ops-phase:*`, `ops-blocked`.

```bash
# Preview the action (no gh write operations)
./scripts/shogun-github-sync.sh --issue 25 --repo OWNER/REPO --dry-run

# Apply (requires gh auth)
./scripts/shogun-github-sync.sh --issue 25 --repo OWNER/REPO
```

## Shogun Ops: watcher (experimental)

Watch the local checkin queue and run `/collect` automatically (useful for the auto/multi-agent loop).

Notes:

- Requires a file watch tool: `fswatch` | `watchexec` | `inotifywait`.
- Ops data lives under `<git-common-dir>/agentic-sdd-ops/`.

```bash
# Show selected watch tool + commands (no watcher required)
./scripts/shogun-watcher.sh --dry-run

# Run continuously: collect on checkin events
./scripts/shogun-watcher.sh

# Test-friendly mode: exit after first event triggers collect
./scripts/shogun-watcher.sh --once
```

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

Optional (opt-in): enable Shogun Ops (checkin/collect/supervise + ops scripts).
Do NOT enable this when you are using an external multi-agent harness (e.g. Oh My OpenCode).

See "External multi-agent harnesses" above for the recommended responsibility split and adaptation guidance.

```
/agentic-sdd --shogun-ops opencode minimal
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

### 4.5) Debug/Investigate (optional)

If you need to debug a bug or run a performance/reliability investigation, use:

```
/debug [issue-number]
```

### 4.6) UI iteration (optional)

For UI-heavy Issues, run short redesign loops with screenshot evidence:

```text
/ui-iterate [issue-number] [route]
```

Helper script example:

```bash
./scripts/ui-iterate.sh 99 --route /kiosk \
  --check-cmd "<typecheck-command>" \
  --check-cmd "<lint-command>" \
  --check-cmd "<test-command>"
```

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
By default, it reviews the branch diff against `origin/main...HEAD` (fallback: `main...HEAD`).

If you set `GH_ISSUE=123`, it reads the Issue body and `- PRD:` / `- Epic:` references
to assemble SoT automatically.

When running tests via `TEST_COMMAND`, you can optionally set `TEST_STDERR_POLICY=fail` to fail-fast
if stderr output is detected (and save it to `tests.stderr`).

### 6) Create PR

After `/review` is approved, push the branch and create a PR:

```
/create-pr [issue-number]
```

`/create-pr` validates that `/review-cycle` metadata still matches the current branch
(`HEAD`, and base SHA when available). If they differ, re-run `/review-cycle`.

If you enable CI (optional), wait for CI checks and fix failures before merging.

---

## Directory Structure

```
.agent/
├── commands/           # command definitions
│   ├── cleanup.md
│   ├── create-prd.md
│   ├── create-epic.md
│   ├── generate-project-config.md
│   ├── create-issues.md
│   ├── create-pr.md
│   ├── debug.md
│   ├── estimation.md
│   ├── impl.md
│   ├── tdd.md
│   ├── ui-iterate.md
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
├── ui-redesign.md
└── worktree-parallel.md

scripts/
├── agentic-sdd              # main CLI
├── assemble-sot.py
├── bench-sdd-docs.py
├── check-commit-gate.py
├── check-impl-gate.py
├── cleanup.sh
├── create-approval.py
├── create-pr.sh
├── extract-epic-config.py
├── extract-issue-files.py
├── generate-project-config.py
├── install-agentic-sdd.sh
├── resolve-sync-docs-inputs.py
├── review-cycle.sh
├── setup-githooks.sh
├── setup-global-agentic-sdd.sh
├── sot_refs.py
├── sync-agent-config.sh
├── ui-iterate.sh
├── validate-approval.py
├── validate-review-json.py
├── worktree.sh
└── tests/                   # test scripts
    ├── test-agentic-sdd-latest.sh
    ├── test-approval-gate.sh
    ├── test-create-pr.sh
    ├── test-install-agentic-sdd.sh
    ├── test-review-cycle.sh
    ├── test-setup-global-agentic-sdd.sh
    ├── test-sync-docs-inputs.sh
    ├── test-ui-iterate.sh
    └── test-worktree.sh

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

| Item             | Default       |
| ---------------- | ------------- |
| Estimation       | Full required |
| Exception labels | Do not use    |
| Technical policy | Simple-first  |
| Q6 Unknowns      | Aim for 0     |

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
