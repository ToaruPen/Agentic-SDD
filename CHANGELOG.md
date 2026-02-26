# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.15] - 2026-02-26

- feat(review-cycle): Add an advisory exploration lane while preserving the main schema v3 review gate contract.
- test(review-cycle): Add hybrid advisory lane compatibility integration tests.
- fix(review-cycle): Default Claude model selection to the `opus` alias.
- docs(flow): Align ralph-loop gate flow with `/test-review` and reflect the `/test-review` gate in workflow docs.
- docs(readme): Clarify that `/pr-bots-review` is optional in the workflow diagram.
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.15` and update README subtree examples to `v0.3.15`.

## [0.3.14] - 2026-02-22

- docs(agents): Clarify fallback policy that when `codex exec` is unavailable (e.g. quota limits), `/review-cycle` and `/test-review` must be executed via Claude tooling without skipping gates.
- docs(agents): Update command summary to state `/review-cycle` default engine (`codex exec`) and Claude fallback.
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.14` and update README subtree examples to `v0.3.14`.

## [0.3.13] - 2026-02-22

- docs(agents): Sync `AGENTS.md` development flow with current command contracts by requiring `/research prd` before `/create-prd`, `/research epic` before `/create-epic`, and `/test-review` before `/review-cycle`/`/create-pr` (including `TEST_REVIEW_DIFF_MODE=range` on committed `HEAD`).
- docs(agents): Clarify `QuestionTool` usage policy with an explicit `ralph-loop` exception that removes per-step user confirmation while keeping the mandatory gate path `/review-cycle -> /final-review -> /create-pr -> /pr-bots-review`.
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.13` and update README subtree examples to `v0.3.13`.

## [0.3.12] - 2026-02-22

- refactor(paths): Standardize all script locations under `scripts/agentic-sdd/` and update documentation references across commands, rules, templates, and skills.
- fix(installer): Migrate legacy `scripts/` target before recursive copy so existing file conflicts are handled gracefully during installation.
- fix(hooks): Add fallback path resolution for gate scripts in `.githooks/pre-commit` and `.githooks/pre-push` to support both new (`scripts/agentic-sdd/`) and legacy paths.
- refactor(sync): Deduplicate validator path resolution in `sync-agent-config.sh` OpenCode gate plugin with shared helper functions.
- fix(worktree): Add fallback sync script path resolution in `worktree.sh` for bootstrap and new commands to maintain backward compatibility.
- test(hooks): Add `test-pre-push-validator-discovery.sh` with 4-scenario matrix coverage for validator discovery fallback paths.
- test(worktree): Extend `test-worktree.sh` with bootstrap and new sync fallback test coverage.
- test(ui-iterate): Add `test-ui-iterate.sh` error handling tests for node bypass detection.
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.12` and update README subtree examples to `v0.3.12`.

## [0.3.11] - 2026-02-21

- docs(ci): Clarify installation and command guidance so the optional `--ci github-actions` template is configured with strict typecheck and test coverage measurement policy (`README.md`, `.agent/commands/init.md`, and `/agentic-sdd` command templates for OpenCode/Codex/Claude).
- docs(epic): Extend Epic toolchain requirements/templates to explicitly include strict typecheck mode and coverage measurement policy (`.agent/commands/create-epic.md`, `.agent/rules/epic.md`, `docs/epics/_template.md`).
- docs(ci-template): Update CI template wording and examples to emphasize coverage-oriented test commands and strict typecheck commands (`templates/ci/github-actions/.github/workflows/agentic-sdd-ci.yml`, `templates/ci/github-actions/scripts/agentic-sdd-ci.sh`).
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.11` and update README subtree examples to `v0.3.11`.

## [0.3.10] - 2026-02-21

- docs(scope-lock): Add explicit branch/issue context preflight checks in `.agent/commands/impl.md` (Phase 1 work-status), `.agent/commands/tdd.md` (Phase 0 gate), `.agent/commands/review-cycle.md` (Phase 0 Scope Lock), and `.agent/commands/worktree.md` (existing-issue continuation), plus high-impact guardrail updates in `AGENTS.md` (Parallel work) and `README.md` (Guardrails).
- docs(sync): Align docs with current behavior by clarifying CI env vars (3 required + optional `AGENTIC_SDD_CI_DOCS_CMD`), updating subtree examples to `v0.3.10`, clarifying `DESIGN.md` as historical context, and fixing command docs for dynamic-check/autofix script references.
- docs(readme): Sync Directory Structure with current tree by adding `docs/memo`, `docs/releasing.md`, `scripts/agentic-sdd/codex-review-event.sh`, `scripts/agentic-sdd/tests/test-codex-review-event.sh`, `scripts/agentic-sdd/tests/test-watch-codex-review.sh`, and `templates/ci/github-actions`.
- chore(release): Bump `scripts/agentic-sdd` `DEFAULT_REF_FALLBACK` to `v0.3.10`.

## [0.3.09] - 2026-02-21

- feat(autofix): Extend the GitHub Actions workflow `templates/ci/github-actions/.github/workflows/agentic-sdd-pr-autofix.yml` to trigger on `issue_comment`, `pull_request_review`, and `pull_request_review_comment`.
- feat(autofix): Update `templates/ci/github-actions/scripts/agentic-sdd-pr-autofix.sh` to normalize multi-event payloads, pass `AGENTIC_SDD_AUTOFIX_EVENT_TYPE`, suppress duplicate source events, and include target SHA/run URL/source event in failure output.
- feat(autofix): After successful autofix push, automatically post `@codex review` with current head SHA.
- docs(autofix): Update `README.md` and `.agent/commands/codex-pr-review.md` to document event-driven autofix loop behavior.
- feat(codex-review): Add event-driven Codex/Coderabbit monitoring workflow at `.github/workflows/codex-review-events.yml` for `issue_comment`, `pull_request_review`, and `pull_request_review_comment` triggers.
- feat(codex-review): Add `scripts/agentic-sdd/codex-review-event.sh` to normalize event payloads, filter allowlisted bot actors, emit consistent PR/type/snippet logs, and fail fast on auth/permission errors.
- docs(codex-review): Update `README.md` and `.agent/commands/codex-pr-review.md` to recommend event-driven monitoring and keep `scripts/agentic-sdd/watch-codex-review.sh` as fallback.
- test(codex-review): Add `scripts/agentic-sdd/tests/test-codex-review-event.sh` coverage for allowlisted processing, non-target no-op behavior, and auth fail-fast path.
- feat(pr-bots-review): Rename `/codex-pr-review` to `/pr-bots-review` and align command docs/config sync references across agent commands and README guidance.
- fix(autofix): Make re-review mention configurable via `AGENTIC_SDD_PR_REVIEW_MENTION` and cover non-target review events in script tests.
- break(review-loop): Require `CODEX_BOT_LOGINS` and `AGENTIC_SDD_AUTOFIX_BOT_LOGINS` to be explicitly configured; missing values now fail fast with actionable error messages.

## [0.3.08] - 2026-02-21

- fix(review-cycle): Switch `REVIEW_CYCLE_INCREMENTAL` default to `1` so reuse is enabled by default in normal review loops.
- docs(review): Update `/review-cycle` and `README.md` guidance to use incremental-by-default with explicit full-run (`REVIEW_CYCLE_INCREMENTAL=0`) before `/final-review`.
- fix(lint-sot): Update evidence URL section parsing to treat `仮説:` / `反証:` / `採否理由:` as candidate section boundaries.
- test(lint-sot): Add regression coverage to ensure URLs outside `根拠リンク:` are not accepted as evidence.
- test(review-cycle): Update default-mode expectation from `incremental-disabled` to `no-previous-run`.

## [0.3.07] - 2026-02-21

- fix(lint-sot): Enforce `仮説:` / `反証:` / `採否理由:` as required candidate fields in `lint_research_contract` to align lint behavior with the `/research` contract.
- test(lint-sot): Add regression coverage that fails when candidate blocks omit `仮説` / `反証` / `採否理由`.
- docs(research): Backfill existing estimation research artifacts under `docs/research/estimation/issue-*` with `仮説` / `反証` / `採否理由` so repository docs remain lint-clean under the updated contract.

## [0.3.06] - 2026-02-21

- fix(lint-sot): Parse external-service comparison table headers by column cells instead of raw substring matching, so malformed single-cell headers no longer pass required-column checks.
- fix(lint-sot): Count comparison data rows only when column counts match the parsed header shape.
- test(lint-sot): Add regression coverage for malformed single-cell comparison table headers.

## [0.3.05] - 2026-02-20

- fix(lint-sot): Count `適用可否:` lines with empty values when enforcing the single-entry rule, preventing bypass with empty+valid duplicate lines in one candidate block.
- test(lint-sot): Add regression coverage for the empty+valid duplicate `適用可否:` bypass pattern.

## [0.3.04] - 2026-02-20

- fix(lint-sot): Reject candidate blocks that contain multiple `適用可否:` lines, preventing enum-check bypass via mixed valid/invalid duplicated entries.
- fix(lint-sot): Keep Markdown table separator parsing tolerant of rows without a trailing `|` in external-service comparison tables.
- test(lint-sot): Add regression coverage for duplicate `適用可否:` lines in a single candidate block.

## [0.3.03] - 2026-02-20

- docs(research): Refine `/research` guidance with explicit exploration-quality prompts (`仮説` / `反証` / `採否理由`) and required exploration-log expectations.
- docs(flow): Add required research quality spot-check phases to `/create-prd`, `/create-epic`, and `/estimation` so downstream generation stops when research artifacts are structurally incomplete.
- docs(template): Update `docs/research/*/_template.md` candidate format with hypothesis/falsification/decision-rationale fields and add mandatory exploration-log sections.
- fix(lint-sot): Validate research candidate `適用可否` values against `Yes / Partial / No` for non-template artifacts.
- test(lint-sot): Add regression coverage for invalid `適用可否` enum values in `scripts/agentic-sdd/tests/test-lint-sot.sh`.

## [0.3.02] - 2026-02-20

- feat: Add Epic research external-service comparison gate to `scripts/agentic-sdd/lint-sot.py` with required structure (`Required` or `Skip(reason)`), concrete service entries, alternative-family coverage, weighted criteria, quantitative table columns, and decision rationale checks.
- test: Extend `scripts/agentic-sdd/tests/test-lint-sot.sh` with positive/negative cases for Epic comparison gate behavior (valid required block, missing section, skip-with-reason, required+skip conflict, empty decision rationale).
- docs: Update Epic research command/template requirements in `.agent/commands/research.md`, `.agent/commands/create-epic.md`, and `docs/research/epic/_template.md` to codify comparison depth expectations.
- docs: Clarify review loop policy in `.agent/commands/review-cycle.md`, `.agent/commands/final-review.md`, and `README.md` (first full baseline, same `scope-id` incremental reruns, fresh full context before `/final-review`, rerun `/review-cycle` when `/final-review` reports `P2+`).

## [0.3.01] - 2026-02-20

- fix: Make `/review-cycle` parse `SOT_FILES` without `readarray` so it works on macOS default Bash 3.2 (`/bin/bash`).
- fix: Run `/review-cycle` `TEST_COMMAND` via `bash -c` with `BASH_ENV` unset to reduce environment-dependent side effects from login/init hooks.
- fix: Keep local-branch precedence in `/review-cycle` remote-ref fetch helper when base refs contain `/` and overlap with remote names.
- test: Add regression coverage for `BASH_ENV` side effects in `/review-cycle` test-command execution path.

## [0.3.00] - 2026-02-19

- Add `/test-review` fail-fast gate documentation and align README PR gate docs with `/create-pr` requirements (`review-metadata` + `test-review-metadata`, range mode on committed HEAD).
- Sync command inventories in `AGENTS.md`/`README.md` with implemented commands (`/research`, `/test-review`) and script listings (`scripts/agentic-sdd/test-review.sh`, `scripts/agentic-sdd/tests/test-test-review.sh`).
- Sync additional command docs for `/init` (and OpenCode alias `/sdd-init`), `/generate-project-config`, `/codex-pr-review`, and `/cleanup` in README/AGENTS quick reference sections.
- Add Codex PR watcher utility (`scripts/agentic-sdd/watch-codex-review.sh`) and document notifier/bot-filter usage in README.
- Clarify Decision Snapshot documentation as index + body split (`docs/decisions.md` index and `docs/decisions/*.md` body files) in README/AGENTS/data-model references.
- Expand README structure/gate docs to reflect actual `docs/` map (`research`, `sot`, `evaluation`, `exec-plans`) and full `scripts/agentic-sdd/`/`scripts/agentic-sdd/tests/` inventory used by quality gates.
- Align `/generate-project-config` command docs with actual output paths under `.agentic-sdd/project/`.
- Make `/create-epic` require repository legibility baselines: project-optimized folder structure design, scoped `AGENTS.md` placement plan, and modern fast lint/format/typecheck toolchain selection with local/CI integration rationale.
- Make global setup write `~/.config/agentic-sdd/default-ref` using remote default-branch detection, and fail fast when detection fails unless `AGENTIC_SDD_DEFAULT_REF` is explicitly set.
- Remove hardcoded `--ref main` from Codex/OpenCode/Claude `agentic-sdd` templates and rely on configured defaults.
- Add `/research` command docs and `docs/research/**` templates to persist reusable research artifacts for PRD/Epic/estimation.
- Make `/create-prd` and `/create-epic` require `/research` as Phase 0, and document conditional `/research estimation` usage.
- Extend `scripts/agentic-sdd/lint-sot.py` (and tests) to lint `docs/research/**` contract requirements.
- Add a GitHub Actions template for PR comment-driven autofix loops (opt-in) and wire it into the installer.
- Add subtree-based update guidance to `README.md` and add `scripts/agentic-sdd/update-agentic-sdd.sh` for deterministic `git subtree pull` updates.
- Add deterministic coverage for subtree updater behavior in `scripts/agentic-sdd/tests/test-update-agentic-sdd.sh`, and verify installer includes the helper script.
- Change `/review-cycle` default diff source to base-branch range (`origin/main...HEAD`, fallback `main...HEAD`) via `DIFF_MODE=range`.
- Add `BASE_REF` support to `/review-cycle` and extend `DIFF_MODE` with `range`.
- Add `/review-cycle` metadata output (`review-metadata.json`) with `head_sha`/`base_ref`/`base_sha`/`diff_sha256`.
- Pin `/review-cycle` metadata `base_sha` to the SHA resolved at range-diff collection time (avoid drift when base refs move during engine execution).
- Add `/create-pr` freshness checks against `review-metadata.json` (fail-fast when reviewed `HEAD` or base SHA has changed).
- Make `/create-pr` fail fast when PR base (`--base` or default) differs from the base branch reviewed in `/review-cycle` metadata.
- Fix local-vs-remote base ref ambiguity for branch names containing `/` (for example `release/v1`) in both `/create-pr` and `/review-cycle`, even when a same-prefix remote exists.
- Fetch remote-tracking base refs (`origin/*`) before `/review-cycle` range diff and `/create-pr` base-SHA freshness checks (while preserving fallback to local `main` when `origin/main` is unavailable).
- Make `DIFF_MODE=range` fail fast when staged/unstaged local changes exist, to avoid reviewing a stale `base...HEAD` patch against a different working-tree state.
- Add deterministic tests for default range diff behavior, empty-range fail-fast, review metadata generation, and `/create-pr` freshness checks.
- Add optional `/review-cycle` incremental reuse (`REVIEW_CYCLE_INCREMENTAL=1`) guarded by strict fingerprint/base/head/diff parity checks, with fail-closed fallback to full execution and reuse observability metadata.
- Add `/ui-iterate` command documentation for iterative UI redesign loops (`capture -> patch -> verify`) with required gate alignment (`/estimation`, `/review-cycle`, `/final-review`).
- Add `skills/ui-redesign.md` and register it in `skills/README.md`.
- Add `scripts/agentic-sdd/ui-iterate.sh` helper to create round folders, run configurable checks, and capture desktop/mobile screenshots.
- Add GitHub Issue template `.github/ISSUE_TEMPLATE/ui-iteration.md` for UI iteration Issues.
- Update command/workflow docs (`AGENTS.md`, `README.md`) to include `/ui-iterate`.
- Remove the obsolete optional orchestration subsystem scripts, command docs, tests, installer flags, and user-facing references from this repository.

## [0.2.39] - 2026-02-11

- Add estimation guidance for deciding which values should be configurable vs hard-coded (record policy in estimate preconditions).

## [0.2.38] - 2026-02-11

- Clarify that Issue/PR titles and bodies must be written in Japanese (allowing Conventional Commit-style prefixes like `feat:` to remain in English).
- Clarify that `/impl` and `/tdd` run `/review-cycle` automatically after implementation; for lightweight changes (e.g. documentation-only updates), ask the user before running it.
- Add `/debug` command documentation for structured debugging/investigation notes (Issue comment or a new Investigation Issue), including performance/reliability evidence fields.
- Add optional, language-agnostic Property-Based Testing (PBT) guidance (recommended for invariant-heavy logic; must be deterministic via fixed randomness/seed).

## [0.2.37] - 2026-02-07

- Fix GitHub Actions `release` workflow to reliably upload assets when a release for the tag already exists (avoid `gh release view` false negatives).
- Use `python3` in Claude Code gate hooks to avoid environments where `python` is missing.

## [0.2.36] - 2026-02-07

- Add `/codex-pr-review` command (Codex bot PR review loop documentation).

## [0.2.35] - 2026-02-06

- Fix `/review-cycle` model selection precedence by adding `--model` and `--claude-model` to `scripts/agentic-sdd/review-cycle.sh` (CLI overrides env defaults).
- Support `--` end-of-options terminator in `scripts/agentic-sdd/review-cycle.sh`.

## [0.2.34] - 2026-02-06

- Change `/review-cycle` default `REASONING_EFFORT` back to `high`.
- Change OpenCode reviewer agent (`sdd-reviewer`) default `reasoningEffort` back to `high`.

## [0.2.33] - 2026-02-06

- Change `/review-cycle` default Codex model to `gpt-5.3-codex` and default `REASONING_EFFORT` to `xhigh`.
- Update OpenCode reviewer agent (`sdd-reviewer`) to `openai/gpt-5.3-codex` with `reasoningEffort: xhigh`.

## [0.2.32] - 2026-02-04

- Add `TEST_STDERR_POLICY` to `/review-cycle` to detect stderr output during `TEST_COMMAND` runs and optionally fail fast; writes `tests.stderr` alongside `tests.txt`.

## [0.2.31] - 2026-01-31

- Improve visibility of external multi-agent harness adaptation guidance (README + `/init`).

## [0.2.30] - 2026-01-31

- Document the recommended approach for using Agentic-SDD with external multi-agent harnesses (treat the harness as the orchestration layer and tailor project `AGENTS.md`/`skills/` accordingly).

## [0.2.28] - 2026-01-30

- Clarify that TDD work still requires running `/review-cycle` after implementation (same as `/impl`).
- Document a practical parent/child Issue pattern for `git worktree`: implement via a single parent Issue while keeping child Issues as tracking-only status observation points.
- Make `/review-cycle` require running tests via `TEST_COMMAND` (allow `TESTS="not run: <reason>"` only).
- Improve `/cleanup` to delete local branches even when no worktree exists (branch match `issue-<n>`).
  - `scripts/agentic-sdd/cleanup.sh`: Parse `git worktree list --porcelain` for branch detection (supports stale worktrees).
  - `scripts/agentic-sdd/tests/test-cleanup.sh`: Regression tests for branch-only cleanup and stale worktree cleanup.

## [0.2.26] - 2026-01-29

- Add `/cleanup` command to safely remove worktrees and local branches after PR merge.
  - `scripts/agentic-sdd/cleanup.sh`: Main cleanup script with safety checks (merge status, uncommitted changes).
  - Support for single Issue cleanup (`/cleanup 123`) and batch cleanup (`/cleanup --all`).
  - Options: `--dry-run`, `--force`, `--skip-merge-check`, `--keep-local-branch`.
- Update workflow documentation to include cleanup as the final step after merge.

## [0.2.24] - 2026-01-28

- Add `/generate-project-config` command to generate project-specific skills/rules from Epic information.
  - `scripts/agentic-sdd/extract-epic-config.py`: Extract tech stack, Q6 requirements, and API design from Epic files.
  - `scripts/agentic-sdd/generate-project-config.py`: Generate files using Jinja2 templates.
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
- Add a benchmark helper to validate `sdd-docs` output size and speed (`scripts/agentic-sdd/bench-sdd-docs.py`).
- Pin OpenCode reviewer agent (`sdd-reviewer`) to `openai/gpt-5.2-codex` with `reasoningEffort: high`.

## [0.2.19] - 2026-01-25

- Fix `extract-issue-files.py --issue-body-file <issue.json>` by allowing JSON `{body: ...}` as an input.
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
- Add `scripts/agentic-sdd/create-pr.sh` and a deterministic offline test for it.

## [0.2.13] - 2026-01-25

- Make `/agentic-sdd` the documented one-time installation entrypoint (README).
- Align `/init` (`/sdd-init`) documentation with the actual installer behavior.
- Add a smoke test for `scripts/agentic-sdd/install-agentic-sdd.sh`.

## [0.2.12] - 2026-01-25

- Clarify deterministic PRD/Epic and diff source resolution for `/sync-docs`.
- Add a tested helper script `scripts/agentic-sdd/resolve-sync-docs-inputs.py` to enforce fail-fast input selection.

## [0.2.11] - 2026-01-25

- Add an implementation gate checklist to prevent skipping estimate/test/quality steps.
- Split estimation from `/impl` into a dedicated `/estimation` command.
- Require Full estimate + explicit user approval before starting `/tdd`.
- Make `/create-issues` require an explicit user choice for GitHub vs local output (no recommendations).
- Strengthen DoD with explicit quality check expectations (or "not run: reason" with approval).
- Document `/tdd` in the README and keep the directory structure listing in sync.

## [0.2.5] - 2026-01-25

- Make `/final-review` the SoT for review taxonomy (P0-P3, status rules) shared by `/review-cycle`.
- Refocus `/review-cycle` docs on the iteration protocol (fix -> re-review) and reference `/final-review` for criteria.
- Update reviewer agent guidance to use P0-P3 and review.json-aligned statuses.
- Merge README review steps into "5) Review (/final-review (/review-cycle))".

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
