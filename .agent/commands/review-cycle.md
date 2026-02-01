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

## Flow

1. Collect the diff (default: `DIFF_MODE=pr`)
2. Run tests (optional) and record results
3. Generate `review.json` via selected engine (`codex exec` or `claude -p`)
4. Validate JSON and save under `.agentic-sdd/`

Note: The review prompt provides:
- `diff.patch` as a local file path (repo-relative)
- a changed-file list

Both engines may open repo files for context, but findings must still be grounded in the diff.

## Iteration protocol (how far/how to loop)

- Run `/review-cycle` at least once before committing (see `/impl`).
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

- `TEST_COMMAND`（推奨: 実行して検証する）
  - `TEST_COMMAND`: command to run tests (e.g. `npm test`). `/review-cycle` が実行して `tests.txt` に全ログを保存する。
- 例外: `TESTS="not run: <reason>"` のみ許可
  - `TESTS`: **実際にテストを実行できない場合のみ**、理由つきで明示する（例: `not run: CI only`）。
  - `TEST_COMMAND` 未指定で `TESTS` が `not run: ...` 以外の場合は fail-fast（レビューの根拠にならないため）。

## Optional inputs (env vars)

- `GH_REPO`: `OWNER/REPO` (when `GH_ISSUE` is not a URL)
- `GH_INCLUDE_COMMENTS`: `1` to include Issue comments in fetched JSON (default: `0`)
- `SOT_MAX_CHARS`: max chars for the assembled SoT bundle (0 = no limit). If exceeded, keep the head and the last ~2KB and insert `[TRUNCATED]`.

- `DIFF_MODE`: `pr` | `auto` | `staged` | `worktree` (default: `pr`)
  - `pr`: review the whole PR/branch diff (`origin/main...HEAD`, fallback `origin/master`, `main`, `master`), including working-tree changes (merge-base → worktree).
    - Note: `git diff` does not include untracked files. If you added new files, `git add` them so they appear in the diff.
  - `auto`: local diffs only. If both staged and worktree diffs exist, fail-fast and ask you to choose.
- `CONSTRAINTS`: additional constraints (default: `none`)

### Engine selection

- `REVIEW_ENGINE`: `codex` | `claude` (default: `codex`)

### Codex options (when `REVIEW_ENGINE=codex`)

- `CODEX_BIN`: codex binary (default: `codex`)
- `MODEL`: Codex model (default: `gpt-5.2-codex`)
- `REASONING_EFFORT`: `minimal` | `low` | `medium` | `high` | `xhigh` (default: `high`)
  - Note: `REASONING_EFFORT=none` is accepted as an alias for `minimal` (backward compatibility).
  - Note: This script passes the value via `codex exec -c model_reasoning_effort=...`, so it overrides global Codex config for the run.

### Claude options (when `REVIEW_ENGINE=claude`)

- `CLAUDE_BIN`: claude binary (default: `claude`)
- `CLAUDE_MODEL`: Claude model (default: `claude-opus-4-5-20250929`)

## Outputs

- `.agentic-sdd/reviews/<scope-id>/<run-id>/review.json`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/diff.patch`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/tests.txt`
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
DIFF_MODE=pr \
MODEL=gpt-5.2-codex \
REASONING_EFFORT=high \
./scripts/review-cycle.sh issue-123
```

Auto-build SoT from a GitHub Issue:

```bash
GH_ISSUE=123 \
TESTS="not run: reason" \
DIFF_MODE=staged \
./scripts/review-cycle.sh issue-123
```

Using Claude as fallback:

```bash
GH_ISSUE=123 \
TESTS="not run: reason" \
DIFF_MODE=staged \
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
