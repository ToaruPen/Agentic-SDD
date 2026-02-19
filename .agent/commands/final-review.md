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

#### If target is an Issue

1. List linked branches (SoT): `gh issue develop --list <issue-number>`.
2. If no linked branch exists, STOP and run `/worktree new --issue <issue-number> --desc "<ascii short desc>"`.
3. `/worktree new` prints the new worktree directory path, but does not change the current shell directory.
4. Run `cd <output-path>` manually.
5. Re-run `/final-review` in that worktree.
6. If linked branches already exist, use `gh issue develop --list <issue-number>` to identify the linked branch; if you are not on it, STOP and switch into that branch/worktree, then run `/final-review`.

#### If target is a PR

1. Read PR head branch: `gh pr view <pr-number> --json headRefName`.
2. If current branch does not match `headRefName`, STOP and switch to the PR head branch/worktree.
3. Run `/final-review` on the PR head branch/worktree.

**Proceed to review phases only after passing all checks above.**

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
- Decisions:
  - Use the **Decision Necessity Checklist** below to classify whether the diff changes decision-level constraints or only wording-level documentation.
  - Decision Snapshot is required when the diff introduces or changes:
    - architecture/major design choices (for example: service boundaries, component ownership, data model boundaries)
    - tooling or vendor selections (for example: new CI/review engine/toolchain vendor choice)
    - security or compliance decisions (for example: auth flow changes, retention/compliance constraints)
    - operational/runbook policies that alter behavior or constraints (for example: deployment topology, release/rollback policy, incident response steps)
  - Decision Snapshot is not required for wording/clarity/example-only edits that do not change behavior or constraints.
  - Decision Necessity Checklist:
    - [ ] Trigger found in this diff (any item above)
    - [ ] Checked `.agent/rules/dod.md` -> section `## Issue done` -> item `重要な判断（why）...Decision Snapshot...index が更新`
    - [ ] Checked `.agent/rules/docs-sync.md` -> section `## Diff classification rules` -> subsection `Decision sync (when "why" changed)`
    - [ ] Checked `.agent/rules/docs-sync.md` -> section `## When a diff is found` for required references and confirmation flow
  - Decision file creation procedure (when checklist result is required):
    - Create `docs/decisions/<decision-file>.md` using naming convention in `docs/decisions/README.md` section `## 命名規約` (`d-YYYY-MM-DD-short-kebab.md`).
    - Start from `docs/decisions/_template.md` and fill required frontmatter/header fields: `Decision-ID`, `Context`, `Rationale`, `Alternatives`, `Impact`, `Verification`, `Supersedes`, `Inputs Fingerprint`.
    - Add/update the decision entry in `docs/decisions.md` under `## Decision Index`.
    - Keep `docs/decisions.md` index and Decision body file references consistent.
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
- Approved with nits:
  - If any `P2` exists: fix `P2+` findings -> run `/review-cycle` -> re-run `/final-review`
  - If findings are `P3` only: if no PR exists, run `/create-pr`; otherwise can merge (optionally batch-fix P3)
- Blocked: fix P0/P1 -> run `/review-cycle` -> re-run `/final-review`
- Question: answer questions (do not guess) -> run `/review-cycle` -> re-run `/final-review`
