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
- This command is intended to run after `/review` is approved.

## Flow

### Phase 0: Preconditions (fail-fast)

Required:

1. You are not on `main` (or `master`).
2. Working tree is clean (no staged/unstaged changes).
3. The Issue has a linked branch, and you are on it:
   - List linked branches (SoT): `gh issue develop --list <issue-number>`
   - If any linked branch exists and you are not on it, report and stop.
4. `/review-cycle` has a passing `review.json` for this Issue scope (`Approved` or `Approved with nits`).
   - If missing or not passing, stop and ask to re-run `/review-cycle`.

### Phase 1: Push

Preferred: use the helper script (does preflight checks and is idempotent):

```bash
./scripts/create-pr.sh --issue <issue-number> --body-file <path>
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

### Phase 3: Output

Report (Japanese):

- Branch name
- Push result (remote tracking)
- PR URL

Notes:

- If CI is enabled for the repo, wait for CI checks and fix failures before merging.

## Related

- `.agent/commands/review.md` - final review gate
- `.agent/commands/review-cycle.md` - local review cycle (review.json)
- `.agent/commands/worktree.md` - worktree + linked branch flow
- `.agent/rules/branch.md` - branch naming rules

## Next command

After PR creation, optionally run `/review <pr-number>` to review the PR diff.
