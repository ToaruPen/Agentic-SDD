# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
