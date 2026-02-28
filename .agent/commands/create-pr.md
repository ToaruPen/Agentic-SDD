# /create-pr

Create a Pull Request for an Issue (push + PR creation).

This command assumes GitHub is the source of truth for Issues and linked branches.
User-facing output remains in Japanese.
PR titles and bodies are user-facing artifacts and must remain in Japanese.
Exception: Conventional Commit-style prefixes at the start of the title (e.g. `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) may remain in English.
Exception: GitHub closing keywords may remain in English (e.g. `Closes #123`, `Fixes #123`).

## Usage

```
/create-pr [issue-number]
```

Notes:

- If omitted, infer the Issue number from the current branch name (`issue-<n>`).
- This command is intended to run after `/final-review` is approved.

## Flow

### Phase 0: Preconditions (fail-fast)

Required:

1. You are not on `main` (or `master`).
2. Working tree is clean (no staged/unstaged changes).
3. Scope Lock verification is completed:
   - Confirm current branch: `git branch --show-current`
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop.
   - If a PR already exists for this branch, verify head branch alignment: `gh pr view <pr-number-or-url> --json headRefName --jq '.headRefName'`
   - If existing PR `headRefName` and current branch differ, report and stop.
4. `/review-cycle` has a passing `review.json` for this Issue scope (`Approved` or `Approved with nits`).
    - If missing or not passing, stop and ask to re-run `/review-cycle`.
    - `review-metadata.json` must match the current branch state:
      - `head_sha` equals current `HEAD`
      - `diff_source` must be `range`
      - if `base_sha` is present, the same `base_ref` still points to that `base_sha`
      - if `base_sha` is present, the PR target base (`--base` or default base) must match the reviewed base branch
5. `/test-review` has a passing `test-review.json` for this Issue scope (`Approved` or `Approved with nits`).
   - If missing or not passing, stop and ask to re-run `/test-review`.
   - `test-review-metadata.json` must match the current branch state:
      - `head_sha` equals current `HEAD`
      - `diff_mode` must be `range`
      - if `base_sha` is present, the same `base_ref` still points to that `base_sha`
      - if `base_sha` is present, the PR target base (`--base` or default base) must match the reviewed base branch
6. Decision Index validation: `python3 scripts/validate-decision-index.py` must pass.
   - This validates: required sections in `docs/decisions/_template.md`, index/body 1:1 correspondence, and Supersedes reference integrity.
   - If the script fails, stop and fix the reported errors before proceeding.
   - The helper script `create-pr.sh` runs this check automatically.

#### Hybrid review-cycle compatibility criteria

When advisory lane is enabled (`REVIEW_CYCLE_ADVISORY_LANE=1`), the contract
between `/review-cycle` and `/create-pr` remains unchanged:

1. **Schema v3 compliance**: `review.json` passes `validate-review-json.py`
   regardless of advisory lane state. `schema_version` must be `3` with all
   required top-level keys (`scope_id`, `status`, `findings`, `questions`,
   `overall_explanation`).
2. **Metadata hard checks**: `/create-pr` hard-checks `head_sha` and
   `diff_source=range`; this contract is unchanged by advisory lane state.
   Current `/review-cycle` always generates `base_sha` as well (required when
   `diff_source=range`). `advisory_lane_enabled` is informational only and is
   not validated by `/create-pr`.
3. **Fail-fast preservation**: Engine failures (`no-output`, `engine-exit`)
   still cause the main review flow to fail with `review_completed=false`
   even when advisory lane is enabled. Advisory lane failures are tolerated
   (non-fatal), but main lane failures are never masked.

Integration tests: `scripts/tests/test-review-cycle.sh` (AC1–AC3 blocks).

### Phase 1: Push

Preferred: use the helper script (does preflight checks and is idempotent):

```bash
./scripts/agentic-sdd/create-pr.sh --issue <issue-number> --body-file <path>
```

Alternatively, push manually:

```bash
git push -u origin HEAD
```

### Phase 2: Create PR

1. If a PR already exists for the current branch, show the PR URL and stop.
2. Otherwise, create a PR via `gh pr create`.

Guidelines:

- Title: reuse the Issue title (or a minimal, accurate title).
- Body must include `Closes #<issue-number>`.
- Keep the body short (1-3 bullets) and focused on "why".

Parent-unit exception:

- When the Issue is a parent implementation unit that must stay open until child tracking Issues are complete,
  use `Refs #<parent-issue-number>` and avoid `Closes/Fixes #<parent-issue-number>`.
- Override the default body via `--body` or `--body-file` (the helper script default is `Closes #<issue-number>`).

### Phase 3: Output

Report (Japanese):

- Branch name
- Push result (remote tracking)
- PR URL

Notes:

- If CI is enabled for the repo, wait for CI checks and fix failures before merging.

## Related

- `.agent/commands/final-review.md` - final review gate
- `.agent/commands/review-cycle.md` - local review cycle (review.json)
- `.agent/commands/worktree.md` - worktree + linked branch flow
- `.agent/rules/branch.md` - branch naming rules

## Next command

After PR creation, optionally run `/final-review <pr-number>` to review the PR diff.
