# Branch Naming Rules

Git branch naming conventions.

---

## Base format

```
<type>/issue-<number>-<short-description>
```

Example: `feature/issue-123-user-registration`

---

## Type

- `feature`: new feature (e.g. `feature/issue-123-user-registration`)
- `fix`: bug fix (e.g. `fix/issue-456-null-pointer`)
- `docs`: documentation (e.g. `docs/issue-789-api-documentation`)
- `refactor`: refactor (e.g. `refactor/issue-101-extract-utils`)
- `test`: tests (e.g. `test/issue-102-add-unit-tests`)
- `chore`: misc (e.g. `chore/issue-103-update-deps`)

---

## Short description

- Lowercase only
- Use hyphens (`-`) between words
- Keep it short (about 3-5 words)
- Start with a verb

Good:

```
feature/issue-123-add-user-profile
fix/issue-456-handle-null-response
refactor/issue-789-extract-validation
```

Bad:

```
feature/issue-123-AddUserProfile     # mixed case
feature/issue-123-add_user_profile   # underscores
feature/123                          # missing description
user-profile                         # missing type and issue number
```

---

## Special branches

- `main`: production release (protected; no direct push)
- `develop`: integration (if used; protected; no direct push)
- `release/*`: release preparation (policy-dependent)
- `hotfix/*`: emergency fixes (policy-dependent)

---

## When there is no Issue number

Use a date or a short id:

```
feature/20240315-quick-fix
chore/tmp-experiment
```

Note: create an Issue whenever possible.

---

## Branch lifetime

- feature: 1-5 days (split if it gets long)
- fix: within 1 day (depending on urgency)
- docs: within 1 day

---

## Delete after merge

Use `/cleanup` to safely remove the worktree and local branch after PR merge:

```bash
# Clean up Issue #123 worktree and local branch
./scripts/agentic-sdd/cleanup.sh 123

# Preview what would be deleted
./scripts/agentic-sdd/cleanup.sh 123 --dry-run

# Clean up all merged worktrees
./scripts/agentic-sdd/cleanup.sh --all
```

Note: Remote branches are automatically deleted by GitHub when PR is merged (if configured).

Manual deletion (if needed):

```bash
# Delete local branch
git branch -d feature/issue-123-user-registration

# Delete remote branch
git push origin --delete feature/issue-123-user-registration
```

---

## Related

- `.agent/rules/commit.md` - commit message rules
- `.agent/rules/issue.md` - issue granularity rules
