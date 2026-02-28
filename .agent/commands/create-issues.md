# /create-issues

Create Issues from an Epic or from a general request.

Issue titles and bodies are user-facing artifacts and must remain in Japanese.
Exception: Conventional Commit-style prefixes at the start of the title (e.g. `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) may remain in English.
Exception: machine-readable keys/tokens used for automation may remain in English (e.g. `- PRD:`, `- Epic:`, `Blocked by:`, label names like `parallel-ok` / `blocked` / `priority:P[0-4]`).

## Usage

```
/create-issues [epic-file]
/create-issues --mode epic --epic-file [epic-file]
/create-issues --mode generic
/create-issues --mode bugfix
/create-issues --mode ops
```

Backward compatibility:

- Existing Epic batch path remains valid: `/create-issues [epic-file]`
- Explicit Epic mode is supported: `/create-issues --mode epic --epic-file [epic-file]`
- If `epic-file` is provided, treat mode as `epic`.

Input parsing (fail-fast):

- `--mode` and positional `epic-file` are mutually exclusive.
- If `--mode` and positional `epic-file` are both provided, print usage and stop immediately.
- If positional `epic-file` is provided (without `--mode`), treat mode as `epic`.
- If neither `--mode` nor positional `epic-file` is provided, print usage and stop immediately.
- If `--mode epic` is specified, `--epic-file` is required.
- If `--mode epic` is specified without `--epic-file`, print usage and stop immediately.

## Flow

### Phase 1: Select creation mode

Choose one mode and fail fast if required inputs are missing.

- `epic` (`/create-issues --mode epic --epic-file [epic-file]` or `/create-issues [epic-file]`): create multiple Issues from an Epic split plan
- `generic`: create a single improvement/chore Issue
- `bugfix`: create a bug fix / urgent response Issue
- `ops`: create an operations/runbook/process Issue

### Phase 2: Collect required inputs (mode-specific, fail-fast)

`epic` mode:

1. Resolve Epic file input from positional `epic-file` or `--epic-file`
2. Read the specified Epic file (fail-fast on file not found, permission denied, or read/parse errors)
3. Extract section 4 (Issue split plan)
4. Identify dependencies
5. Stop if section 4 cannot be extracted

`generic` / `ops` mode:

1. Collect minimal traceability fields:
   - 根拠リンク (URL or repo path)
   - 起票目的 (what this Issue unlocks/improves)
   - 検証条件 (observable done condition)
2. Include Epic/PRD reference as a link or `N/A (reason)`
3. Stop if any minimal traceability field is missing, or if Epic/PRD reference (`link` or `N/A (reason)`) is missing

`bugfix` mode:

1. Collect bug evidence (`根拠リンク`) and impact
2. Include Epic/PRD references, or write `N/A (reason)` when unavailable
3. Include `起票目的` and reproduction or incident context
4. Define `検証条件` (observable fix confirmation)
5. Select exactly one priority (P0-P4); do not select multiple priorities
6. Add matching `priority:P[0-4]` label
7. Stop if evidence, impact, Epic/PRD reference (or `N/A (reason)`), purpose, reproduction or incident context, or verification condition is missing, if priority is missing or multiple priorities are selected, or if `priority:P[0-4]` label is missing

### Phase 3: Granularity check

Each Issue must satisfy:

- LOC: 50-300
- Files: 1-5
- AC: 2-5

### Phase 4: Split/merge signals

Too large (split needed):

- Expected LOC > 300
- Files >= 6
- AC >= 6
- Multiple verbs ("do A and B and C")

Too small (consider merging):

- Expected LOC < 50
- Only 1 AC
- Always done together with another Issue

### Phase 5: Exception labels

If an Issue violates the rules, apply an exception label and fill all required fields (see `.agent/rules/issue.md`).

- `bulk-format`
- `test-heavy`
- `config-risk`
- `refactor-scope`

### Phase 6: Generate the Issue body

Use the Issue body template in `.agent/rules/issue.md`.
Always include:

- Epic/PRD references (or `N/A (reason)`)
- Minimal traceability fields (`根拠リンク` / `起票目的` / `検証条件`)
- AC (observable)
- Estimated change size
- Dependencies ("Blocked by" + "what becomes possible")
- If bug fix / urgent response: select P0-P4 in the body and add `priority:P[0-4]` label

### Phase 7: Create Issues

GitHub Issues are the required output destination.

1. If `--dry-run` is set, do not call `gh issue create`; render and display generated Issue title/body/labels/assignees, print `Preview only (--dry-run): no GitHub Issue created.`, and exit.
2. If `--dry-run` is not set, preflight the environment:
   - Check git remotes: `git remote -v`
   - Check GitHub auth: `gh auth status`
3. If `--dry-run` is not set, create Issues via `gh issue create` and print `Issue created on GitHub.`
4. If the environment is not ready (no `gh`, not authenticated, wrong repo), stop and ask the user to fix it.

## Output format

GitHub Issues:

```bash
gh issue create --title "[title]" --body "[body]" --label "[labels]"
```

## Options

- `--mode [epic|generic|bugfix|ops]`: select creation mode. `--mode epic` requires `--epic-file [path]`. Do not combine `--mode` with positional `epic-file`. `--mode` can be combined with `--dry-run` and `--start`.
- `--epic-file [path]`: required when `--mode epic` is used
- `--dry-run`: preview only
- `--start [number]`: start from a specific Issue number

## Related

- `.agent/rules/issue.md` - issue granularity rules
- `.agent/rules/epic.md` - epic generation rules
- `.agent/rules/docs-sync.md` - documentation sync rules

## Next command

After Issues are created, run `/estimation`, then `/impl` or `/tdd`.
