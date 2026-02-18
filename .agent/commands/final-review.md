# /final-review

Review a PR or an Issue.

This command is the SoT for review taxonomy (status/priority) shared by:

- `/final-review` (human-readable Japanese review output)
- `/review-cycle` (machine-readable `review.json` output)

User-facing output remains in Japanese.

## Usage

```text
/final-review <PR-number | Issue-number>
```

Target is mandatory. Do not infer from the current branch.

## Flow

### Phase 0: Preconditions (fail-fast)

1. Target must be explicitly provided (`PR-number` or `Issue-number`).
   - If omitted, STOP and ask the user to specify the target.
2. Validate branch/worktree context explicitly before review.
   - If target is an Issue:
     - List linked branches (SoT): `gh issue develop --list <issue-number>`
     - If no linked branch exists, STOP and create one via `/worktree new --issue <issue-number> --desc "<ascii short desc>"`.
     - `/worktree new` prints the new worktree directory path, but does not change the current shell directory. Run `cd <output-path>` manually, then re-run `/final-review` in that worktree.
     - If linked branches already exist, use `gh issue develop --list <issue-number>` to identify the linked branch, switch into that branch/worktree manually, then run `/final-review`.
   - If target is a PR:
     - Read PR head branch: `gh pr view <pr-number> --json headRefName`
     - If current branch does not match `headRefName`, STOP and switch to the PR head branch/worktree.
3. Only after 1-2 pass, continue to review phases.

### Phase 1: Identify the target

1. Identify the PR number or Issue number
2. Identify related PRD and Epic
3. Collect the list of changed files

### Phase 2: Run `/sync-docs` (required)

Run `/sync-docs` before reviewing.

Output format: see `.agent/rules/docs-sync.md` (single source of truth).

### Phase 3: Review taxonomy (required)

#### Priorities (P0-P3)

- P0: must-fix (correctness/security/data-loss)
- P1: should-fix (likely bug / broken tests / risky behavior)
- P2: improvement (maintainability/perf minor)
- P3: nit (small clarity)

#### Status (`review.json.status`)

- `Approved`: `findings=[]` and `questions=[]`
- `Approved with nits`: findings may exist but must not include `P0`/`P1`; `questions=[]`
- `Blocked`: must include at least one `P0`/`P1` finding
- `Question`: must include at least one question

Recommended status selection precedence:

1. If any `P0`/`P1` finding exists -> `Blocked`
2. Else if any question exists -> `Question`
3. Else if any finding exists -> `Approved with nits`
4. Else -> `Approved`

#### Scope rules

- Only flag issues introduced by this diff (do not flag pre-existing issues).
- Be concrete; avoid speculation; explain impact.
- Ignore trivial style unless it obscures meaning or violates documented standards.
- For each finding, include evidence (`file:line`).

#### `review.json` shape (schema v3; used by `/review-cycle`)

- Required keys: `schema_version`, `scope_id`, `status`, `findings`, `questions`, `overall_explanation`
- Finding keys:
  - `title`: short title
  - `body`: 1 short paragraph (Markdown allowed)
  - `priority`: `P0|P1|P2|P3`
  - `code_location.repo_relative_path`: repo-relative path
  - `code_location.line_range`: `{start,end}` (keep as small as possible; overlap the diff)

### Phase 4: DoD check

Follow `.agent/rules/dod.md`.

### Phase 5: Verify AC

Verify each AC one-by-one.

Keep it concise; include "how verified" and evidence.

### Phase 6: Review focus areas

- Correctness: does it satisfy AC / PRD / Epic?
- Decisions: if the diff contains new/changed "why", verify Decision Snapshot (`docs/decisions/`) exists and `docs/decisions.md` index is updated
- Readability: names, structure, consistency
- Testing: meaningful assertions, enough coverage
- Security: input validation, auth, secret handling
- Performance: obvious issues

### Phase 7: Compare against the estimate

Compare actuals vs estimate.

Record LOC/files/effort vs estimate; if the gap is large, explain why.

### Phase 8: Output the review result

Write a short Japanese review with:

- Status (Approved / Approved with nits / Blocked / Question)
- GitHub recommended action (Approve / Request changes / Comment)
- sync-docs summary (no diff / diff approved / diff needs action)
- DoD status (see `.agent/rules/dod.md`)
- AC verification summary (how verified + evidence)
- Findings (P0-P3) with `file:line` evidence
- Questions (if any)
- Overall explanation

## How to handle sync-docs results

- No diff: ready to merge
- Diff (minor): record the diff and proceed
- Diff (major): update PRD/Epic before merging

## Options

- `--quick`: only sync-docs + AC verification
- `--full`: full review across all focus areas
- `--ac-only`: only AC verification

## Related

- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/commands/sync-docs.md` - sync-docs command

## Next steps

- Approved: if no PR exists, run `/create-pr`; otherwise can merge
- Approved with nits: if no PR exists, run `/create-pr`; otherwise can merge (optionally batch-fix P2/P3)
- Blocked: fix P0/P1 -> run `/review-cycle` -> re-run `/final-review`
- Question: answer questions (do not guess) -> run `/review-cycle` -> re-run `/final-review`
