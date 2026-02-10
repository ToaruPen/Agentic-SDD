# /create-issues

Create Issues from an Epic.

Issue titles and bodies are user-facing artifacts and must remain in Japanese.
Exception: Conventional Commit-style prefixes at the start of the title (e.g. `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) may remain in English.
Exception: machine-readable keys/tokens used for automation may remain in English (e.g. `- PRD:`, `- Epic:`, `Blocked by:`, label names like `parallel-ok` / `blocked` / `priority:P[0-4]`).

## Usage

```
/create-issues [epic-file]
```

## Flow

### Phase 1: Read the Epic

1. Read the specified Epic file
2. Extract section 4 (Issue split plan)
3. Identify dependencies

### Phase 2: Granularity check

Each Issue must satisfy:

- LOC: 50-300
- Files: 1-5
- AC: 2-5

### Phase 3: Split/merge signals

Too large (split needed):

- Expected LOC > 300
- Files >= 6
- AC >= 6
- Multiple verbs ("do A and B and C")

Too small (consider merging):

- Expected LOC < 50
- Only 1 AC
- Always done together with another Issue

### Phase 4: Exception labels

If an Issue violates the rules, apply an exception label and fill all required fields (see `.agent/rules/issue.md`).

- `bulk-format`
- `test-heavy`
- `config-risk`
- `refactor-scope`

### Phase 5: Generate the Issue body

Use the Issue body template in `.agent/rules/issue.md`.
Always include:

- Epic/PRD references
- AC (observable)
- Estimated change size
- Dependencies ("Blocked by" + "what becomes possible")
- If bug fix / urgent response: select P0-P4 in the body and add `priority:P[0-4]` label

### Phase 6: Create Issues

Confirm the output destination with the user (do not recommend).

1. If GitHub Issues are an option, preflight the environment:
   - Check git remotes: `git remote -v`
   - Check GitHub auth: `gh auth status`
2. Present choices (no "recommended" label):
   - Create GitHub Issues via `gh issue create`
   - Output local markdown files under `issues/`
3. Follow the user's selection.
4. If the user does not choose, run `--dry-run` and stop.

## Output format

GitHub Issues:

```bash
gh issue create --title "[title]" --body "[body]" --label "[labels]"
```

Local files:

```
issues/
- 001-setup.md
- 002-db-schema.md
- 003-user-api.md
```

## Options

- `--dry-run`: preview only
- `--local`: output local files instead of GitHub Issues
- `--start [number]`: start from a specific Issue number

## Related

- `.agent/rules/issue.md` - issue granularity rules
- `.agent/rules/epic.md` - epic generation rules
- `.agent/rules/docs-sync.md` - documentation sync rules

## Next command

After Issues are created, run `/estimation`, then `/impl` or `/tdd`.
