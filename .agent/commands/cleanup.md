# /cleanup

Clean up worktree and local branch after PR merge.

This command safely removes worktrees and local branches for completed Issues.
Remote branches are NOT deleted (handled by GitHub on PR merge).

## Usage

```
/cleanup [issue-number | --all] [options]
```

Options:

- `--all`: Clean up all merged worktrees + local branches
- `--dry-run`: Show what would be deleted (no actual deletion)
- `--force`: Force delete even with uncommitted changes
- `--skip-merge-check`: Skip merge status verification
- `--keep-local-branch`: Delete worktree only, keep local branch

Examples:

```bash
/cleanup 123              # Clean up Issue #123
/cleanup 123 --dry-run    # Preview what would be deleted
/cleanup --all            # Clean up all merged worktrees
/cleanup --all --dry-run  # Preview all cleanups
```

## Flow

### Phase 0: Preconditions (fail-fast)

Required:

1. Git is available.
2. You are in a git repository.
3. If `gh` is available, it will be used for enhanced merge detection.

### Phase 1: Identify targets

For single Issue:

1. Find the worktree associated with the Issue number (by path or branch name pattern `issue-<n>`).
2. Determine the branch name from the worktree.
3. If no worktree is found, fall back to the local branch match (`issue-<n>`) and delete the branch (after safety checks).

For `--all`:

1. List all worktrees (excluding main repo).
2. Filter to only merged branches (via `git branch --merged` or `gh pr list --state merged`).

### Phase 2: Safety checks

For each target:

1. **Merge status**: Verify the branch is merged into main (skip with `--skip-merge-check`).
2. **Uncommitted changes**: Check for staged/unstaged changes (override with `--force`).

If checks fail, report warnings and skip the target (unless overridden).

### Phase 3: Execute cleanup

For each target:

1. Remove the worktree via `git worktree remove`.
2. Delete the local branch via `git branch -d` (skip with `--keep-local-branch`).

### Phase 4: Output report

Report (Japanese):

- Number of cleaned up worktrees
- Number of skipped/failed targets (if any)
- Warnings for unmerged or dirty worktrees

## Script

Use the helper script:

```bash
./scripts/agentic-sdd/cleanup.sh [issue-number | --all] [options]
```

## Related

- `.agent/commands/create-pr.md` - PR creation (run before cleanup)
- `.agent/commands/worktree.md` - worktree creation
- `.agent/rules/branch.md` - branch naming rules
- `skills/worktree-parallel.md` - parallel implementation workflow

## Workflow position

```
/impl -> /review-cycle -> /final-review -> /create-pr -> [Merge] -> /cleanup
```

After PR is merged, run `/cleanup` to remove the worktree and local branch.
