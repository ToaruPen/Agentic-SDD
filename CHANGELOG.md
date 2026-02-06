# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Fix `scripts/review-cycle.sh` model selection precedence by adding `--model` and `--claude-model` CLI options (CLI overrides env defaults).

## [0.2.34] - 2026-02-06

- Change `/review-cycle` default `REASONING_EFFORT` back to `high`.
- Change OpenCode reviewer agent (`sdd-reviewer`) default `reasoningEffort` back to `high`.

## [0.2.33] - 2026-02-06

- Change `/review-cycle` default Codex model to `gpt-5.3-codex` and default `REASONING_EFFORT` to `xhigh`.
- Update OpenCode reviewer agent (`sdd-reviewer`) to `openai/gpt-5.3-codex` with `reasoningEffort: xhigh`.

## [0.2.32] - 2026-02-04

- Add optional tmux shim to open Shogun Ops tmux layout via `tmux --shogun-ops` (opt-in; requires putting `scripts/` first in `PATH`).
  - `scripts/tmux`: Intercepts `--shogun-ops` and runs `scripts/shogun-tmux.sh init` + `attach`; forwards all other calls to the real tmux binary.
  - `scripts/install-agentic-sdd.sh`: Exclude `scripts/tmux` unless `--shogun-ops` is enabled.
  - `scripts/tests/test-tmux-shogun-ops.sh`: Deterministic tests for `--shogun-ops` dry-run and forwarding behavior.
  - `scripts/tests/test-install-agentic-sdd.sh`: Ensure the shim is installed only with `--shogun-ops`.
- Add `TEST_STDERR_POLICY` to `/review-cycle` to detect stderr output during `TEST_COMMAND` runs and optionally fail fast; writes `tests.stderr` alongside `tests.txt`.

## [0.2.31] - 2026-01-31

- Improve visibility of external multi-agent harness adaptation guidance (README + `/init`).

## [0.2.30] - 2026-01-31

- Document the recommended approach for using Agentic-SDD with external multi-agent harnesses (treat the harness as the orchestration layer and tailor project `AGENTS.md`/`skills/` accordingly).

## [0.2.29] - 2026-01-31

- Make Shogun Ops installation opt-in via `--shogun-ops`.
  - `scripts/install-agentic-sdd.sh`: Exclude Shogun Ops commands/scripts unless explicitly enabled.
  - `scripts/agentic-sdd`: Forward `--shogun-ops` to the installer.
  - `scripts/tests/test-install-agentic-sdd.sh`: Add deterministic coverage for default-off and opt-in installs.
  - README / `.agent/commands/init.md`: Document the new opt-in flag and external harness warning.
- Add Shogun Ops (research loop) decision-centric research request/response flow.
  - `scripts/shogun-ops.py`: Extend `/checkin` with `--respond-to-decision` to link a research response deterministically to a decision.
  - `scripts/shogun-ops.py`: Treat `blocker` reasons prefixed with `調査依頼:` as research requests (`request.category=research`) and attach minimal `issue_context` (repo/number/title/url/labels).
  - `scripts/shogun-ops.py`: During `/collect`, apply research responses to the referenced decision, auto-archive resolved decisions to `archive/decisions/`, and avoid mutating Issue progress/assignee from response checkins.
  - `scripts/shogun-ops.py`: Add `decision --id DEC-...` to show decision YAML from `queue/decisions` or `archive/decisions`.
  - `scripts/tests/test-shogun-ops.sh`: Add deterministic integration tests for research request decision creation, response application, and auto-archiving.
  - `.agent/commands/checkin.md`: Document research request/response usage.

## [0.2.28] - 2026-01-30

- Add Shogun Ops `/refactor-draft` (Lower-only) to write refactor candidate drafts under `queue/refactor-drafts/` for Middle to turn into Issues.
  - `scripts/shogun-ops.py`: Add `refactor-draft` subcommand and ops layout directory.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration test for draft creation and append-only behavior.
  - `.agent/commands/refactor-draft.md`: Command documentation.
- Add Shogun Ops `/refactor-issue` (Middle-only) to create GitHub Issues from `queue/refactor-drafts/` and archive drafts after success.
  - `scripts/shogun-ops.py`: Add `refactor-issue` subcommand (label bootstrap + issue create + archive).
  - `scripts/tests/test-shogun-refactor-issue.sh`: Offline deterministic test with `gh` stub.
  - `.agent/commands/refactor-issue.md`: Command documentation.
- Add Shogun Ops (auto) watcher to run `collect` automatically on checkin events.
  - `scripts/shogun-watcher.sh`: Watch `queue/checkins/` and run `shogun-ops.py collect` with retry and `--once` support.
  - `scripts/tests/test-shogun-watcher.sh`: Deterministic tests for retries and watchexec `--once` capability checks.
- Clarify that TDD work still requires running `/review-cycle` after implementation (same as `/impl`).
- Document a practical parent/child Issue pattern for `git worktree`: implement via a single parent Issue while keeping child Issues as tracking-only status observation points.
- Add Shogun Ops `/skill --approve <decision-id>` to generate `skills/<name>.md`, update `skills/README.md`, and archive the approved `skill_candidate` decision.
- Add Shogun Ops (core) action-required queue derived from decisions generated at collect time.
  - `scripts/shogun-ops.py`: Extend `/checkin` to capture `needs.*` (approval/contract-expansion/blockers), emit `queue/decisions/*.yaml` (SoT) during `/collect`, and derive `state.yaml.action_required` + dashboard section.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration tests for decision generation and de-duplication.
  - `.agent/commands/checkin.md`: Document new `/checkin` flags.
- Add Shogun Ops (core) contract drift detection and state-based supervision policy.
  - `scripts/shogun-ops.py`: During `/collect`, compare `changes.files_changed` vs `contract.allowed_files/forbidden_files` and emit a decision + block on drift.
  - `scripts/shogun-ops.py`: During `/supervise --once`, assign orders only to idle workers based on `state.yaml` (busy phases: estimating/implementing/reviewing); treat `max_workers` as an upper bound.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration tests for the above behaviors.
- Add Shogun Ops skill candidates (checkin → collect → decisions).
  - `scripts/shogun-ops.py`: Allow `/checkin` to include `candidates.skills[]` and emit `type=skill_candidate` decisions during `/collect` with de-duplication.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration tests for `skill_candidate` decision generation and de-duplication.
  - `.agent/commands/checkin.md`: Document `/checkin` flags for skill candidates.
- Make `/review-cycle` require running tests via `TEST_COMMAND` (allow `TESTS="not run: <reason>"` only).
- Add Shogun Ops (skill candidates) dashboard section to list pending `decision(type=skill_candidate)` items (name/summary).
  - `scripts/shogun-ops.py`: Derive `state.yaml.skill_candidates_pending` from decisions and render it in `dashboard.md`.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration test for decisions-only refresh + dashboard listing.
- Add Shogun Ops (auto) tmux launcher for deterministic session/pane layout and order injection.
  - `scripts/shogun-tmux.sh`: Create tmux session with fixed pane titles (`upper`, `middle`, `ashigaru1`, `ashigaru2`, `ashigaru3`), send-order via pane title lookup (independent of `pane-base-index`), and dry-run support.
  - `scripts/shogun-tmux.sh`: Add `--send-keys-mode single|two-step` to reduce send-keys injection flakiness by splitting cmd and Enter into separate tmux calls.
  - `scripts/tests/test-shogun-tmux.sh`: Deterministic tests for dry-run output and missing-tmux fail-fast behavior.
  - README: Add "Shogun Ops: tmux launcher" section with usage examples.
- Add Shogun Ops (auto) GitHub sync to reflect local ops state to an Issue (Middle-only).
  - `scripts/shogun-github-sync.sh`: Add a status comment and update labels (`ops-phase:*`, `ops-blocked`).
  - `scripts/tests/test-shogun-github-sync.sh`: Offline deterministic test with `gh` stub (success + auth failure).
  - README: Add "Shogun Ops: GitHub sync" section with usage examples.
- Improve `/cleanup` to delete local branches even when no worktree exists (branch match `issue-<n>`).
  - `scripts/cleanup.sh`: Parse `git worktree list --porcelain` for branch detection (supports stale worktrees).
  - `scripts/tests/test-cleanup.sh`: Regression tests for branch-only cleanup and stale worktree cleanup.

## [0.2.27] - 2026-01-29

- Add Shogun Ops (core Phase 1) initializer under `git-common-dir` and `/status` dashboard command.
  - `scripts/shogun-ops.py`: Initialize `agentic-sdd-ops/` and render `dashboard.md`.
  - `.agent/commands/status.md`: `/status` command documentation.
  - `scripts/tests/test-shogun-ops.sh`: Deterministic integration test (temp git repo).
- Add Shogun Ops (core Phase 2) `/checkin` command to create append-only checkin YAML files.
  - `.agent/commands/checkin.md`: `/checkin` command documentation.
- Add Shogun Ops (core Phase 2) `/collect` command to update `state.yaml` and `dashboard.md` from checkins with a single-writer lock.
  - `.agent/commands/collect.md`: `/collect` command documentation.
- Add Shogun Ops (core Phase 3) `/supervise --once` to select targets from GitHub Issues, detect overlaps via `worktree.sh check`, and emit orders/decisions.
  - `.agent/commands/supervise.md`: `/supervise` command documentation.
- Expand deterministic tests for Shogun Ops core (Phase 1–3) including `gh` stubs and overlap detection.
- Prevent queue corruption under fast/multi-target supervise runs:
  - Avoid per-worker order overwrites by writing orders under `queue/orders/<worker>/` with per-order filenames.
  - Ensure decision IDs are unique even when multiple decisions are emitted in quick succession.

## [0.2.26] - 2026-01-29

- Add `/cleanup` command to safely remove worktrees and local branches after PR merge.
  - `scripts/cleanup.sh`: Main cleanup script with safety checks (merge status, uncommitted changes).
  - Support for single Issue cleanup (`/cleanup 123`) and batch cleanup (`/cleanup --all`).
  - Options: `--dry-run`, `--force`, `--skip-merge-check`, `--keep-local-branch`.
- Update workflow documentation to include cleanup as the final step after merge.

## [0.2.24] - 2026-01-28

- Add `/generate-project-config` command to generate project-specific skills/rules from Epic information.
  - `scripts/extract-epic-config.py`: Extract tech stack, Q6 requirements, and API design from Epic files.
  - `scripts/generate-project-config.py`: Generate files using Jinja2 templates.
  - `templates/project-config/`: Template files for config.json, security.md, performance.md, api-conventions.md, and tech-stack.md.
- Update install script to include `templates/project-config/` and `requirements-agentic-sdd.txt`.

## [0.2.23] - 2026-01-28

- Add Claude Code as a fallback review engine for `/review-cycle` via `REVIEW_ENGINE=claude`.
- Support Extended Thinking (`--betas interleaved-thinking`) by default for Claude engine.
- Fix Claude CLI integration: extract `structured_output` from wrapped response, pass schema content instead of file path, and remove `$schema` meta field.

## [0.2.22] - 2026-01-27

- Add production quality rules (performance/security/observability/availability) and update PRD/Epic templates accordingly.
- Translate LLM-facing rule/command docs to English to reduce prompt bloat.
- Fix `setup-global-agentic-sdd.sh` to skip rewriting unchanged config files (avoids unnecessary `.bak.*` backups).

## [0.2.21] - 2026-01-26

- Align bugfix priority range to P0-P4 and document priority labels in `/create-issues`.
- Add guidance to fill project-specific metrics in `/create-epic`.
- Register new skills (anti-patterns, data-driven, resource limits) and list them in docs.

## [0.2.20] - 2026-01-25

- Add an OpenCode documentation explorer agent (`sdd-docs`) to generate minimal Context Packs for the Agentic-SDD workflow.
- Add a benchmark helper to validate `sdd-docs` output size and speed (`scripts/bench-sdd-docs.py`).
- Pin OpenCode reviewer agent (`sdd-reviewer`) to `openai/gpt-5.2-codex` with `reasoningEffort: high`.

## [0.2.19] - 2026-01-25

- Fix `worktree.sh check --issue-body-file <issue.json>` by allowing JSON `{body: ...}` as an input to `extract-issue-files.py`.
- Keep UTF-8 (no `\\uXXXX` escapes) when `validate-review-json.py --format` rewrites `review.json`.
- Add offline tests covering the above behaviors.

## [0.2.18] - 2026-01-25

- Add `--ref latest` support to `agentic-sdd` (resolves to the highest semver tag).
- Default Codex/Claude/Clawdbot/OpenCode `/agentic-sdd` templates to install `--ref latest`.
- Bundle `CHANGELOG.md` into the installed Codex skill directory via `setup-global-agentic-sdd.sh`.
- Add offline tests for the above behaviors.

## [0.2.17] - 2026-01-25

- Add technical enforcement for the `/estimation` approval gate via local approval records + hooks:
  - OpenCode plugin (`.opencode/plugins/agentic-sdd-gate.js`) blocks edit/write and git commit/push.
  - Git hooks (`.githooks/`) provide a tool-agnostic final defense line (pre-commit + pre-push).
  - Claude Code hooks (`.claude/settings.json`) block edit/write and git commit/push.

## [0.2.16] - 2026-01-25

- Reduce prompt/context bloat by de-duplicating doc templates and pointing commands/agents to canonical rule sources.
- Improve `assemble-sot.py` truncation to preserve the last ~2KB of content, with a regression test.

## [0.2.15] - 2026-01-25

- Add opt-in GitHub Actions CI template installation via `--ci github-actions` (no workflows are installed by default).

## [0.2.14] - 2026-01-25

- Add `/create-pr` to push the linked branch and create a PR via `gh`.
- Add `scripts/create-pr.sh` and a deterministic offline test for it.

## [0.2.13] - 2026-01-25

- Make `/agentic-sdd` the documented one-time installation entrypoint (README).
- Align `/init` (`/sdd-init`) documentation with the actual installer behavior.
- Add a smoke test for `scripts/install-agentic-sdd.sh`.

## [0.2.12] - 2026-01-25

- Clarify deterministic PRD/Epic and diff source resolution for `/sync-docs`.
- Add a tested helper script `scripts/resolve-sync-docs-inputs.py` to enforce fail-fast input selection.

## [0.2.11] - 2026-01-25

- Add an implementation gate checklist to prevent skipping estimate/test/quality steps.
- Split estimation from `/impl` into a dedicated `/estimation` command.
- Require Full estimate + explicit user approval before starting `/tdd`.
- Make `/create-issues` require an explicit user choice for GitHub vs local output (no recommendations).
- Strengthen DoD with explicit quality check expectations (or "not run: reason" with approval).
- Document `/tdd` in the README and keep the directory structure listing in sync.

## [0.2.5] - 2026-01-25

- Make `/review` the SoT for review taxonomy (P0-P3, status rules) shared by `/review-cycle`.
- Refocus `/review-cycle` docs on the iteration protocol (fix -> re-review) and reference `/review` for criteria.
- Update reviewer agent guidance to use P0-P3 and review.json-aligned statuses.
- Merge README review steps into "5) Review (/review (/review-cycle))".

## [0.2.4] - 2026-01-25

- Document `/init` as the one-time workflow entrypoint (OpenCode: `/sdd-init`).
- Require release hygiene in `AGENTS.md` (changelog + release + pinned script updates).
- Add `--ref <tag>` example to the Codex `agentic-sdd` skill.

## [0.2.3] - 2026-01-25

- Add Issue "in progress" locking to `worktree.sh new` using `gh issue develop` linked branches.
- Make `/review-cycle` a required local gate before committing in `/impl`.
- Add linked-branch work status checks to `/impl` Phase 1 to prevent duplicate work.

## [0.2.2] - 2026-01-25

- Simplify `review.json` schema (v3) by removing unused fields and enforcing strict keys.
- Switch review finding priority from numeric `0-3` to labeled `P0-P3`.

## [0.2.1] - 2026-01-24

- Sync the `agentic-sdd` skill into OpenCode via a symlink to the Codex skill directory.
- Harden `agentic-sdd` argument parsing under `set -u`.

## [0.2.0] - 2026-01-24

- Add deterministic parallel implementation support with `git worktree` helpers and `/worktree` docs.
- Add `/review-cycle` with SoT auto-assembly from GitHub Issues and local validation.
- Translate agent-facing control docs to English.

## [0.1.0] - 2026-01-23

- Initial release.
