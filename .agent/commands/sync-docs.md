# /sync-docs

Check consistency across PRD, Epic, and implementation.

User-facing output remains in Japanese.

## Usage

```
/sync-docs [prd-file]
```

If omitted, auto-detect the PRD related to the current branch.

## Flow

### Phase 1: Collect inputs

1. Identify PRD file (`docs/prd/*.md`)
2. Identify related Epic file (`docs/epics/*.md`)
3. Collect implementation changes (git diff or specified range)

### Phase 1.5: Resolve inputs deterministically (required)

<success_criteria>
- You can name exactly one PRD, exactly one Epic, and exactly one diff source.
- If any of them is ambiguous, STOP and ask the user (do not guess).
</success_criteria>

<prd_epic_resolution>
PRD resolution priority:

1. If `prd-file` argument is provided: use it.
2. Else, prefer the GitHub Issue body (when available):
   - If `GH_ISSUE` is set: fetch the Issue and read `- PRD:` / `- Epic:`.
   - Else, if the current branch contains `issue-<number>`: treat it as the Issue number and fetch it.
3. Else, if exactly one file matches `docs/prd/*.md`: use it.
4. Else: STOP and ask the user to specify the PRD (and Epic).

Epic resolution priority:

1. Prefer `- Epic:` from the Issue body.
2. Else, if PRD is known: find the Epic whose `参照PRD:` matches the PRD path.
   - If multiple Epics match: STOP and ask.
   - If no Epic matches: STOP and ask.

Fail-fast:

- If `- PRD:` / `- Epic:` exists but is empty/placeholder (e.g. contains `<!--`), STOP and ask to fix the Issue body.
- If multiple candidates exist at any step, STOP and ask.
</prd_epic_resolution>

<diff_resolution>
Diff source selection (deterministic):

1. If reviewing a PR (explicit PR number, or a PR exists for the current branch): use the PR diff (base...head).
2. Else, use local diffs:
   - If both staged and worktree diffs are non-empty: STOP and ask which to use (`staged` vs `worktree`).
   - Else if staged diff is non-empty: use staged diff.
   - Else if worktree diff is non-empty: use worktree diff.
   - Else: use range diff (`origin/main...HEAD`, fallback `main...HEAD`).
</diff_resolution>

Helper (recommended):

- Run `python3 scripts/agentic-sdd/resolve-sync-docs-inputs.py` to resolve PRD/Epic and diff source with fail-fast behavior.

### Phase 2: Detect diffs

Check diffs from these angles:

- Functional requirements: PRD section 4 vs Epic design / code
- AC: PRD section 5 vs tests / implementation
- Out of scope: PRD Q5 vs implementation scope
- Technical constraints: PRD Q6 vs Epic tech choices

### Phase 3: Classify diffs

- Spec change: PRD requirements changed (action: update PRD)
- Interpretation change: PRD interpretation changed (action: update Epic)
- Implementation-driven: changes due to technical constraints (action: record reason / fix code)

### Phase 4: Output the report

Use the canonical output template defined in `.agent/rules/docs-sync.md`.

## When to run

- When creating a PR: required (DoD)
- After merge: recommended
- During implementation when making a large change: recommended

## Options

- `--verbose`: show detailed diffs
- `--fix`: apply safe auto-fixes (with confirmation)
- `--epic [file]`: check a specific Epic only

## Related

- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/rules/dod.md` - Definition of Done

## Notes

- References (PRD/Epic/code) are required; do not omit.
- Do not ignore diffs implicitly.
- Do not modify higher-level docs (PRD) without explicit confirmation.
