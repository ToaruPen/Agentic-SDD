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
/agentic-sdd* -> /create-prd -> /create-epic -> /generate-project-config** -> /create-issues -> /estimation -> /impl|/tdd -> /ui-iterate*** -> /review-cycle -> /final-review -> /create-pr -> [Merge] -> /cleanup
     |            |              |              |                            |              |            |              |              |            |            |                         |
     v            v              v              v                            v              v            v              v              v            v            v                         v
     Install       7 questions    3-layer guard  Generate project            LOC-based       Full estimate Implement      UI round loop  Local loop    DoD gate       Push + PR create       Remove worktree
                  + checklist    + 3 required   skills/rules                50-300 LOC      + approval    + tests        capture/verify review.json   + sync-docs    (gh)                   + local branch
```

\*\* Optional: generates project-specific skills/rules based on Epic tech stack and Q6 requirements.

\*\*\* Optional: recommended for iterative UI redesign Issues.

\* One-time install of Agentic-SDD workflow files in the repo.
Optional: enable GitHub-hosted CI (GitHub Actions) via `/agentic-sdd --ci github-actions` and enforce it with branch protection.

Required gate notes:

- `/research prd` is required before `/create-prd`.
- `/research epic` is required before `/create-epic`.
- `/research estimation` is required before `/estimation` when estimate preconditions are unknown.
- `/create-pr` requires passing outputs from both `/review-cycle` and `/test-review` on committed `HEAD` with range diff metadata.

---

## External multi-agent harnesses

If you are using an external multi-agent harness, treat it as the **single orchestration layer** (agent lifecycle, task queue, state/progress tracking, parallel execution).

Use Agentic-SDD as the workflow/rules layer (PRD → Epic → Issues → estimation gates → review gates), and tailor your project's `AGENTS.md` and `skills/` to match the harness's operating model.

In other words:

- External harness = orchestration SoT (state/progress)
- Agentic-SDD = spec-driven workflow + quality gates

---

## Parallel Implementation (git worktree)

Agentic-SDD supports deterministic parallel implementation by running one Issue per branch/worktree.

Guardrails:

- Each Issue must declare `### 変更対象ファイル（推定）` (used as the conflict-check input)
- Only mark Issues as `parallel-ok` when declared file sets are disjoint
- Before high-impact actions (`/review-cycle`, `/create-pr`, `/pr-bots-review`, manual conflict resolution), run a Scope Lock check and stop on mismatch (`git branch --show-current` + `gh issue develop --list <issue>` + `gh pr view <pr> --json headRefName`).

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

After install, edit `.github/workflows/agentic-sdd-ci.yml` and set the 3 required env vars to your project's commands.
You can optionally set `AGENTIC_SDD_CI_DOCS_CMD` if you want docs checks in CI.
To enforce in GitHub, require the check `agentic-sdd-ci / ci` via branch protection rules.

If you do not have `/agentic-sdd` yet, set it up once by cloning this repo and running:

```bash
./scripts/setup-global-agentic-sdd.sh
```

Use `full` instead of `minimal` if you want GitHub issue/PR templates.

After installation, OpenCode exposes Agentic-SDD's init checklist as `/sdd-init` (because `/init` is built-in).

### 0.5) Update existing installs with git subtree (recommended)

If Agentic-SDD is already installed in your repository and you want repeatable updates without manual re-import,
use `git subtree` with a fixed prefix (for example `.agentic-sdd-upstream`).

One-time setup in each target repository:

```bash
git subtree add --prefix=.agentic-sdd-upstream https://github.com/ToaruPen/Agentic-SDD.git v0.3.10 --squash
```

Then update by tag/branch:

```bash
git subtree pull --prefix=.agentic-sdd-upstream https://github.com/ToaruPen/Agentic-SDD.git v0.3.10 --squash
```

This repository also includes a helper script for the pull step:

```bash
./.agentic-sdd-upstream/scripts/update-agentic-sdd.sh --ref v0.3.10
```

Notes:

- Prefer pinned tags for deterministic updates.
- Avoid chained subtree setups (`subtree -> subtree`); each consumer repo should pull directly from this repo.
- Keep local customizations outside the subtree prefix (for example `.agentic-sdd.local/`) to reduce merge friction.
- Avoid using `.agentic-sdd/` as subtree prefix because it is used for runtime artifacts.

### 1) Create a PRD

Run PRD research first (required):

```
/research prd [project-name]
```

```
/create-prd [project-name]
```

Answer 7 questions to create a PRD. Q6 is choice-based; at least one negative/abnormal AC is required.

### 2) Create an Epic

Run Epic research first (required):

```
/research epic [prd-file]
```

```
/create-epic [prd-file]
```

Create a technical plan and an Issue split proposal. Three lists are required:
external services / components / new tech.

### 2.5) Generate project-specific config (optional)

If you want project-tailored rules/skills generated from the Epic:

```
/generate-project-config [epic-file]
```

### 3) Create Issues

```
/create-issues [epic-file]
```

Create Issues following the granularity rules (50-300 LOC).

### 4) Implement

Create a worktree for the Issue (required):

```
/worktree new --issue <issue-number> --desc "<ascii short desc>"
```

Then run implementation inside that worktree.

Implementation requires a Full estimate + explicit user approval gate.
If an approved estimate does not exist yet, `/impl` and `/tdd` will run `/estimation` first and stop for approval.

```
/estimation [issue-number]
```

If estimate assumptions are still unclear, run estimation research first:

```
/research estimation [issue-number]
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

### 5) Review (`/final-review` (`/review-cycle`))

Before `/review-cycle` and `/create-pr`, run fail-fast test review:

```text
/test-review [scope-id] [run-id]
```

Use `TEST_REVIEW_DIFF_MODE=range` on committed `HEAD` before `/create-pr`.
`TEST_REVIEW_PREFLIGHT_COMMAND` is required for `/test-review` execution.

Final gate:

```
/final-review <PR-number | Issue-number>
```

Run the DoD check and `/sync-docs`.

`/final-review` fail-fast essentials:

- Target is mandatory (`/final-review <PR-number | Issue-number>`).
- Run on the linked Issue branch/worktree or PR head branch/worktree.

During development (and before committing, per `/impl`), iterate locally with:

```
/review-cycle [scope-id]
```

`/review-cycle` generates `review.json` and is meant to be used in a fix -> re-review loop.
By default, it reviews the branch diff against `origin/main...HEAD` (fallback: `main...HEAD`).
In this default (`DIFF_MODE=range`), the working tree must be clean; for pre-commit local changes, use `DIFF_MODE=staged` or `DIFF_MODE=worktree`.

`/review-cycle` fail-fast essentials:

- `scope-id` is mandatory.
- One SoT input source is required (`SOT` or `GH_ISSUE` or `GH_ISSUE_BODY_FILE`).
- One test evidence source is required (`TEST_COMMAND` or `TESTS="not run: <reason>"`).

Recommended incremental operation:

- Keep `REVIEW_CYCLE_INCREMENTAL=1` + `REVIEW_CYCLE_CACHE_POLICY=balanced` during normal issue loops (default behavior).
- If you want to avoid reusing non-Approved results (`Blocked`/`Question`) on exact no-change loops, set `REVIEW_CYCLE_CACHE_POLICY=strict`.
- When a fresh full baseline is needed, set `REVIEW_CYCLE_INCREMENTAL=0` (or `REVIEW_CYCLE_CACHE_POLICY=off`) explicitly.
- Before `/final-review`, run one fresh full local review context (do not rely only on reused incremental artifacts).
- If `/final-review` reports any `P2` or higher finding (`P0/P1/P2`), fix it and run `/review-cycle` again, then re-run `/final-review`.

Note: the review engine invocation (`codex exec` by default) has no timeout by default. If you need one, set `EXEC_TIMEOUT_SEC` (uses `timeout`/`gtimeout` when available).

If you set `GH_ISSUE=123`, it reads the Issue body and `- PRD:` / `- Epic:` references
to assemble SoT automatically.

When running tests via `TEST_COMMAND`, you can optionally set `TEST_STDERR_POLICY=fail` to fail-fast
if stderr output is detected (and save it to `tests.stderr`).

### 6) Create PR

After `/final-review` is approved, push the branch and create a PR:

```
/create-pr [issue-number]
```

`/create-pr` validates that `/review-cycle` metadata still matches the current branch
(`HEAD`, and base SHA when available). If they differ, re-run `/review-cycle`.

It also validates `/test-review` metadata for the current branch state
(`HEAD`, `diff_mode=range`, and base SHA alignment when available).

`/create-pr` fail-fast essentials:

- Do not run on `main`/`master`.
- Working tree must be clean.
- Run on the Issue-linked branch/worktree.

If you enable CI (optional), wait for CI checks and fix failures before merging.

Recommended: use event-driven monitoring via `.github/workflows/codex-review-events.yml`.
It triggers on `issue_comment` / `pull_request_review` / `pull_request_review_comment`,
filters to configured bot accounts (`CODEX_BOT_LOGINS`, required), and logs PR number/URL/type/snippet
in a consistent format.

Fallback: watch review-bot feedback locally and trigger a local hook on new comments/reviews.

For CI-based autofix loops, use `templates/ci/github-actions/.github/workflows/agentic-sdd-pr-autofix.yml`.
It handles `issue_comment` / `pull_request_review` / `pull_request_review_comment`, passes
comment body + PR number + normalized event type (`issue_comment`/`review`/`inline`) to
`AGENTIC_SDD_AUTOFIX_CMD`, executes autofix only on the target PR's HEAD branch,
and re-requests the configured review mention (`AGENTIC_SDD_PR_REVIEW_MENTION`) after successful push.

```bash
CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' \
scripts/watch-codex-review.sh --pr 96
```

To integrate with your own notifier, pass `--notify-cmd` (or `CODEX_REVIEW_HOOK`):

```bash
CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' \
CODEX_REVIEW_HOOK='osascript -e "display notification \"$CODEX_EVENT_TYPE\" with title \"PR Review Bot\""' \
scripts/watch-codex-review.sh --pr 96
```

To watch additional bot accounts, set `CODEX_BOT_LOGINS` as a comma-separated list:

```bash
CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' \
scripts/watch-codex-review.sh --pr 96
```

For autofix re-review requests, set the mention string explicitly:

```bash
AGENTIC_SDD_PR_REVIEW_MENTION='@pr-bots review'
```

### 6.5) PR review-bot loop (optional)

To request and iterate review-bot checks on a PR:

```text
/pr-bots-review <PR_NUMBER_OR_URL>
```

### 7) Cleanup after merge

After merge, remove worktree/local branch for the Issue:

```text
/cleanup [issue-number]
```

Batch cleanup for merged Issue branches:

```text
/cleanup --all
```

---

## Directory Structure

```
.agent/
├── commands/           # command definitions
│   ├── cleanup.md
│   ├── pr-bots-review.md
│   ├── create-prd.md
│   ├── create-epic.md
│   ├── generate-project-config.md
│   ├── create-issues.md
│   ├── create-pr.md
│   ├── debug.md
│   ├── estimation.md
│   ├── impl.md
│   ├── init.md
│   ├── research.md
│   ├── tdd.md
│   ├── test-review.md
│   ├── ui-iterate.md
│   ├── review-cycle.md
│   ├── final-review.md
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
├── memo/
├── releasing.md        # release/tag operation notes
├── research/            # reusable research artifacts
│   ├── prd/
│   ├── epic/
│   └── estimation/
├── sot/
│   └── README.md        # SoT index (map-not-manual)
├── evaluation/
│   ├── quality-gates.md # pass/fail gate definitions
│   └── quality-score.md # optional health scoring
├── exec-plans/
│   ├── index.md         # execution plan index
│   └── _template.md
├── decisions.md        # Decision index (Decision Snapshot)
├── decisions/
│   ├── README.md       # Decision body operation rules
│   └── _template.md    # Decision body template
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
├── codex-review-event.sh
├── create-approval.py
├── create-pr.sh
├── extract-epic-config.py
├── extract-issue-files.py
├── generate-project-config.py
├── install-agentic-sdd.sh
├── lint-sot.py
├── resolve-sync-docs-inputs.py
├── review-cycle.sh
├── setup-githooks.sh
├── setup-global-agentic-sdd.sh
├── sot_refs.py
├── sync-agent-config.sh
├── test-review.sh
├── watch-codex-review.sh
├── update-agentic-sdd.sh
├── ui-iterate.sh
├── validate-approval.py
├── validate-review-json.py
├── validate-worktree.py
├── worktree.sh
└── tests/                   # test scripts
    ├── test-agentic-sdd-latest.sh
    ├── test-approval-gate.sh
    ├── test-codex-review-event.sh
    ├── test-create-pr.sh
    ├── test-install-agentic-sdd.sh
    ├── test-lint-sot.sh
    ├── test-ruff-format-gate.sh
    ├── test-ruff-gate.sh
    ├── test-ruff-prepush-new-branch-no-new-commits.sh
    ├── test-test-review.sh
    ├── test-cleanup.sh
    ├── test-review-cycle.sh
    ├── test-setup-global-agentic-sdd.sh
    ├── test-sync-docs-inputs.sh
    ├── test-update-agentic-sdd.sh
    ├── test-ui-iterate.sh
    ├── test-watch-codex-review.sh
    └── test-worktree.sh

templates/
├── ci/                 # optional CI templates
│   └── github-actions/
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

See `DESIGN.md` for design rationale and historical context.
For the current operational structure/commands, use this README and `.agent/` as source of truth.

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

This repo provides global definitions (OpenCode/Codex/Claude) and a helper CLI `agentic-sdd`
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

### Implementation gate enforcement (recommended)

To prevent accidental implementation without required gates, Agentic-SDD can enforce local gates:

- Worktree gate: enforce that Issue branches are worked on in a linked worktree (`/worktree new`).
- Approval gate: enforce that `/estimation` has an explicit user approval record.

- Git hooks (tool-agnostic final defense): `.githooks/pre-commit`, `.githooks/pre-push`
  - Enable: `./scripts/setup-githooks.sh` (the installer attempts to configure this automatically)
- Claude Code: `.claude/settings.json` (PreToolUse hooks: Edit/Write + git commit/push)
- OpenCode: `.opencode/plugins/agentic-sdd-gate.js` (generated by `./scripts/sync-agent-config.sh opencode`)

Gate scripts:

- `scripts/validate-worktree.py`
- `scripts/validate-approval.py`

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
