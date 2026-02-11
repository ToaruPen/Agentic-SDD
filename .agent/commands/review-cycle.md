# /review-cycle

Iterate locally during development using:

"review (JSON) -> fix -> re-review (JSON)".

This command uses `codex exec` (default) or `claude -p` to generate `review.json` (review result JSON).
The final gate remains `/review` (DoD + `/sync-docs`).

Review taxonomy (status/priority) and output rules are defined in:

- `.agent/commands/review.md` (SoT)

## Usage

```
/review-cycle <scope-id> [run-id]
```

- `scope-id`: identifier like `issue-123` (`[A-Za-z0-9._-]+`)
- `run-id`: optional; defaults to reusing `.agentic-sdd/reviews/<scope-id>/.current_run` or a timestamp

Underlying script:

```bash
./scripts/review-cycle.sh <scope-id> [run-id] [--dry-run] [--model MODEL] [--claude-model MODEL]
```

## Flow

1. Collect the diff (default: `DIFF_MODE=range`, `BASE_REF=origin/main`)
2. Run tests (optional) and record results
3. Generate `review.json` via selected engine (`codex exec` or `claude -p`)
4. Validate JSON and save under `.agentic-sdd/`

## Iteration protocol (how far/how to loop)

- Run `/review-cycle` at least once before committing (see `/impl`).
  Exception: for lightweight changes (e.g. documentation-only updates), ask the user whether to run it; skipping requires explicit approval and a recorded reason.
- After each run, decide next action based on `review.json.status`:
  - `Blocked`: fix all `P0`/`P1` findings and re-run.
  - `Question`: answer questions (do not guess). If you cannot answer from the repo, stop and ask the user, then re-run after clarifying.
  - `Approved with nits`: optionally batch-fix `P2`/`P3` (do not chase style-only churn). If you change code, re-run once.
  - `Approved`: stop and proceed.
- Do not re-run without a code/spec change.
- Rule of thumb: converge within 1-3 cycles. If you are still `Blocked`/`Question` after ~3 meaningful attempts, stop and escalate (likely missing/contradicting SoT or scope too large).

## Required inputs (env vars)

### SoT (one required)

- `SOT`: manual SoT string (paths/links/summary)
- `GH_ISSUE`: GitHub Issue number or URL (fetched via `gh issue view`)
- `GH_ISSUE_BODY_FILE`: local file containing an Issue body (test/offline)
- `SOT_FILES`: extra local files to include (repo-relative, space-separated)

### Tests (one required)

- `TEST_COMMAND` (recommended: actually run tests)
  - `TEST_COMMAND`: command to run tests (e.g. `npm test`). `/review-cycle` runs it and writes full logs to `tests.txt`.
  - `TEST_STDERR_POLICY`: `warn` | `fail` | `ignore` (default: `warn`)
    - `warn`: print a warning when stderr is detected (exit code still follows `TEST_COMMAND`)
    - `fail`: fail fast when stderr is detected (stop before running the review engine)
    - `ignore`: record stderr but do not use it for gating
    - Note: Vitest-style `stderr | ...` “stderr reports” are also treated as stderr signals.
- Exception: `TESTS="not run: <reason>"` is allowed only when you truly cannot run tests
  - `TESTS`: an explicit reasoned summary (e.g. `not run: CI only`).
  - If `TEST_COMMAND` is not set and `TESTS` is not `not run: ...`, `/review-cycle` fails fast (because it is not valid evidence).

## Optional inputs (env vars)

- `GH_REPO`: `OWNER/REPO` (when `GH_ISSUE` is not a URL)
- `GH_INCLUDE_COMMENTS`: `1` to include Issue comments in fetched JSON (default: `0`)
- `SOT_MAX_CHARS`: max chars for the assembled SoT bundle (0 = no limit). If exceeded, keep the head and the last ~2KB and insert `[TRUNCATED]`.

- `DIFF_MODE`: `range` | `auto` | `staged` | `worktree` (default: `range`)
  - `range`: review `BASE_REF...HEAD` (default `BASE_REF=origin/main`, fallback to `main` if `origin/main` is missing)
    - Requires a clean working tree (no staged/unstaged changes). For pre-commit local changes, use `staged` or `worktree`.
  - If both staged and worktree diffs exist in `auto`, fail-fast and ask you to choose.
- `BASE_REF`: base ref for `range` mode (default: `origin/main`; fallback to `main`)
- `CONSTRAINTS`: additional constraints (default: `none`)

### Engine selection

- `REVIEW_ENGINE`: `codex` | `claude` (default: `codex`)

### Codex options (when `REVIEW_ENGINE=codex`)

- `CODEX_BIN`: codex binary (default: `codex`)
- `MODEL`: Codex model (default: `gpt-5.3-codex`)
- `REASONING_EFFORT`: `high` | `medium` | `low` (default: `high`)

### Claude options (when `REVIEW_ENGINE=claude`)

- `CLAUDE_BIN`: claude binary (default: `claude`)
- `CLAUDE_MODEL`: Claude model (default: `claude-opus-4-5-20250929`)

## Outputs

- `.agentic-sdd/reviews/<scope-id>/<run-id>/review.json`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/review-metadata.json`
  - In `DIFF_MODE=range`, `base_sha` is pinned to the SHA resolved when `diff.patch` is collected.
- `.agentic-sdd/reviews/<scope-id>/<run-id>/diff.patch`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/tests.txt`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/tests.stderr`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/sot.txt`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/prompt.txt`

## SoT auto-ingest behavior

- If `GH_ISSUE` or `GH_ISSUE_BODY_FILE` is set, include the Issue body in SoT
- Parse `- Epic:` / `- PRD:` lines in the Issue body, read referenced `docs/epics/...` / `docs/prd/...`, and include them
  - PRD/Epic are included as a "wide excerpt" (the initial `##` section plus `## 1.` to `## 8.`)
  - If `- Epic:` / `- PRD:` exists but cannot be resolved, fail-fast

## Examples

Using Codex (default):

```bash
SOT="docs/prd/example.md docs/epics/example.md" \
TEST_COMMAND="npm test" \
REASONING_EFFORT=high \
./scripts/review-cycle.sh issue-123 --model gpt-5.3-codex
```

Auto-build SoT from a GitHub Issue:

```bash
GH_ISSUE=123 \
TESTS="not run: reason" \
./scripts/review-cycle.sh issue-123
```

Using Claude as fallback:

```bash
GH_ISSUE=123 \
TESTS="not run: reason" \
REVIEW_ENGINE=claude \
./scripts/review-cycle.sh issue-123
```

## Notes on Claude engine

- Claude Opus 4.5 has a 200K token context window (half of Codex's 400K).
- Extended Thinking is enabled by default (`--betas interleaved-thinking`) to enhance reasoning.
- For large PRD + Epic + diff combinations, consider setting `SOT_MAX_CHARS` (e.g., 80000-120000).
- Use Claude when Codex is unavailable or as a secondary opinion.

## Related

- `.agent/commands/review.md` - final gate (DoD + `/sync-docs`)
- `.agent/schemas/review.json` - review JSON schema (schema v3)
