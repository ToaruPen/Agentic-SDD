# /worktree

Set up and manage `git worktree`-based parallel implementation.

This workflow is designed to be deterministic and fail-fast:

- Do not allow "parallel" labeling when change targets overlap or are unknown.
- Prefer explicit inputs (Issue body files / declared change targets) over inference.

User-facing output remains in Japanese.

## Usage

```
/worktree <subcommand> [args]
```

Subcommands map to `./scripts/agentic-sdd/worktree.sh`:

- `new`: create a worktree + branch for an Issue
- `bootstrap`: generate tool configs in an existing worktree (OpenCode/Codex)
- `check`: detect overlap between Issues (deterministic conflict guard)
- `list`: list worktrees
- `remove`: remove a worktree

## Preconditions (deterministic parallel)

To allow parallel work, each Issue MUST include a declared file list under:

- `### 変更対象ファイル（推定）`

Paths MUST be repo-relative and SHOULD be wrapped in backticks:

```markdown
- [ ] `src/foo.ts`
- [ ] `src/bar/baz.ts`
```

If the list is missing or empty, treat the Issue as `blocked` (not parallel).

## Flow

### Phase 1: Collect targets

1. Identify the Issues you want to run in parallel.
2. Ensure each Issue body contains `### 変更対象ファイル（推定）`.
3. Ensure dependencies are explicitly stated (`Blocked by` section).

### Phase 2: Check overlap (required)

Run the overlap checker before applying `parallel-ok`.

Examples:

```bash
# Check GitHub Issues (requires gh)
./scripts/agentic-sdd/worktree.sh check --issue 123 --issue 124
```

If overlaps exist, fail-fast and:

- Split Issues to avoid overlap, OR
- Convert to explicit dependencies (`blocked`) and serialize.
- Create a single "parent" Issue as the implementation unit, and keep the overlapping Issues as tracking-only children (do not create branches/worktrees for child Issues).

### Phase 3: Create worktrees (one Issue = one branch = one worktree)

Create a separate branch/worktree per Issue.

`./scripts/agentic-sdd/worktree.sh new` will also create a linked branch on the GitHub Issue via
`gh issue develop` (SoT for "in progress"). It fails fast if the Issue already has
linked branches.

Scope lock before continuing from an existing Issue context:

- Always confirm current branch: `git branch --show-current`
- Always list linked branches for the Issue: `gh issue develop --list <issue-number>`
- If there are multiple linked branches for the same Issue, stop and choose one branch/worktree explicitly before implementation or conflict resolution.

If you are using a parent/child structure, run `./scripts/agentic-sdd/worktree.sh new` only for the parent Issue (implementation unit). Child Issues remain branch-less and are updated via comments/checklists.

```bash
./scripts/agentic-sdd/worktree.sh new --issue 123 --desc "add user profile" --tool opencode
./scripts/agentic-sdd/worktree.sh new --issue 124 --desc "add settings page" --tool opencode
```

### Phase 4: Work in parallel

Open one terminal per worktree directory and implement independently.

Merge in a "finish one, merge one" manner to reduce conflicts.

### Phase 5: Review gate

For each Issue, run:

- `/review-cycle` (required)
- `/final-review` (required; includes `/sync-docs`)

## Options

See `./scripts/agentic-sdd/worktree.sh --help`.

## Related

- `.agent/rules/issue.md` - dependency + `parallel-ok` rules
- `.agent/rules/branch.md` - branch naming
- `skills/worktree-parallel.md` - patterns/checklists
- `scripts/agentic-sdd/worktree.sh` - deterministic wrapper
