# /review-cycle

Iterate locally during development using:

"review (JSON) -> fix -> re-review (JSON)".

This command uses `codex exec` to generate `review.json` (review result JSON).
The final gate remains `/review` (DoD + `/sync-docs`).

## Usage

```
/review-cycle <scope-id> [run-id]
```

- `scope-id`: identifier like `issue-123` (`[A-Za-z0-9._-]+`)
- `run-id`: optional; defaults to reusing `.agentic-sdd/reviews/<scope-id>/.current_run` or a timestamp

## Flow

1. Collect the diff (default: `DIFF_MODE=auto`)
2. Run tests (optional) and record results
3. Generate `review.json` via `codex exec --output-schema`
4. Validate JSON and save under `.agentic-sdd/`

## Required inputs (env vars)

### SoT (one required)

- `SOT`: manual SoT string (paths/links/summary)
- `GH_ISSUE`: GitHub Issue number or URL (fetched via `gh issue view`)
- `GH_ISSUE_BODY_FILE`: local file containing an Issue body (test/offline)
- `SOT_FILES`: extra local files to include (repo-relative, space-separated)

### Tests (one required)

- `TESTS` or `TEST_COMMAND`
  - `TESTS`: short test summary (can be `not run: reason`)
  - `TEST_COMMAND`: command to run tests (e.g. `npm test`)

## Optional inputs (env vars)

- `GH_REPO`: `OWNER/REPO` (when `GH_ISSUE` is not a URL)
- `GH_INCLUDE_COMMENTS`: `1` to include Issue comments in fetched JSON (default: `0`)
- `SOT_MAX_CHARS`: max chars for the assembled SoT bundle (0 = no limit). If exceeded, cut and append `[TRUNCATED]`.

- `DIFF_MODE`: `auto` | `staged` | `worktree` (default: `auto`)
  - If both staged and worktree diffs exist in `auto`, fail-fast and ask you to choose.
- `MODEL`: Codex model (default: `gpt-5.2-codex`)
- `REASONING_EFFORT`: `high` | `medium` | `low` (default: `high`)
- `CONSTRAINTS`: additional constraints (default: `none`)

## Outputs

- `.agentic-sdd/reviews/<scope-id>/<run-id>/review.json`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/diff.patch`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/tests.txt`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/sot.txt`

## SoT auto-ingest behavior

- If `GH_ISSUE` or `GH_ISSUE_BODY_FILE` is set, include the Issue body in SoT
- Parse `- Epic:` / `- PRD:` lines in the Issue body, read referenced `docs/epics/...` / `docs/prd/...`, and include them
  - PRD/Epic are included as a "wide excerpt" (the initial `##` section plus `## 1.` to `## 8.`)
  - If `- Epic:` / `- PRD:` exists but cannot be resolved, fail-fast

## Status and next action

Decide next actions based on `review.json.status`:

- `Approved`: stop (next is `/review`)
- `Approved with nits`: usually stop (batch-fix nits; optionally re-run once)
- `Blocked`: continue (fix priority 0/1 and re-run)
- `Question`: continue (answer questions and re-run; if you cannot answer, define policy/spec first)

## Examples

```bash
SOT="docs/prd/example.md docs/epics/example.md" \
TEST_COMMAND="npm test" \
DIFF_MODE=auto \
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

## Related

- `.agent/commands/review.md` - final gate (DoD + `/sync-docs`)
- `.agent/schemas/review.json` - review JSON schema (review-v2 compatible)
