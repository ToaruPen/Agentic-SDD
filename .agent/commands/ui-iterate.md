# /ui-iterate

Iterate UI redesign in short loops:

"capture -> review -> patch -> verify -> re-capture".

This command is for visual/UX convergence on one Issue.
It does not bypass implementation gates (`/estimation`, tests, `/review-cycle`, `/final-review`).

User-facing output remains in Japanese.

## Usage

```
/ui-iterate <issue-number> [route]
```

Examples:

```text
/ui-iterate 99 /kiosk
/ui-iterate 99 /staff
```

Underlying helper script:

```bash
./scripts/agentic-sdd/ui-iterate.sh <issue-number> [round-id] --route /kiosk \
  --check-cmd "<project-typecheck-command>" \
  --check-cmd "<project-lint-command>" \
  --check-cmd "<project-test-command>"
```

Issue template (recommended):

```text
.github/ISSUE_TEMPLATE/ui-iteration.md
```

Optional knobs (in your execution plan / prompt):

- `max-rounds` (default: 3)
- `viewports` (default: desktop + mobile)

## Flow

### Phase 0: Implementation gate (required)

Before the first redesign round:

1. Ensure linked branch/worktree is correct (`gh issue develop --list <issue-number>`).
2. Ensure an approved Full estimate exists (`/estimation <issue-number>`).
3. If no approval exists, STOP and run `/estimation` first.

### Phase 1: Fix scope (SoT)

1. Read Issue, related Epic, and PRD.
2. Extract AC and non-goals.
3. Define target route and viewports (desktop/mobile).
4. Define per-round scope: max 1-3 UI problems per round.

Rule: do not mix unrelated backend/domain changes into UI rounds.

### Phase 2: Baseline capture

1. Capture baseline screenshots for each target viewport.
2. Save under:

```
var/screenshot/issue-<n>/round-00/
```

3. Record first findings (P0-P3 style):
   - P0/P1: usability breakage (cannot operate, misleading state, blocked interaction)
   - P2: major visual hierarchy/readability issues
   - P3: nits

### Phase 3: Redesign loop (repeat)

For each round `01..max-rounds`:

1. Pick up to 3 highest-impact findings.
2. Apply minimal UI changes.
3. Run verification with project-standard commands (`typecheck`, `lint`, `test`, and runtime smoke when needed).
4. Capture screenshots and save under:

```
var/screenshot/issue-<n>/round-<xx>/
```

5. Compare with previous round and record:
   - improved points
   - regressions
   - remaining issues

Stop conditions:

- AC satisfied for this Issue, and no P0/P1 findings remain
- or reached `max-rounds` (then report residuals and propose a follow-up Issue)

### Phase 4: Mandatory gates before commit

After final round:

1. Run `/review-cycle` for the Issue scope and fix findings until Approved/Approved with nits.
2. Run `/final-review` (DoD + `/sync-docs` gate).

### Phase 5: Output

Provide concise Japanese report:

- rounds executed
- what changed (by impact)
- verification results
- screenshot paths
- residual issues (if any)
- recommended next command (`/create-pr` or follow-up Issue)

Template:

```text
UI反復を完了しました（Issue #<n>）。

- 実施ラウンド: <x>/<max>
- 主要改善: <3点まで>
- 検証: typecheck/lint/test(/e2e) の結果
- スクリーンショット:
  - var/screenshot/issue-<n>/round-00/...
  - var/screenshot/issue-<n>/round-01/...
  - ...
- 残課題: <なし / あり>

次のステップ:
1. /create-pr
2. （必要なら）残課題を別Issue化
```

## Related

- `skills/ui-redesign.md` - UI redesign principles/checklist
- `skills/crud-screen.md` - screen design checklist
- `.agent/commands/estimation.md` - Full estimate + approval gate
- `.agent/commands/review-cycle.md` - local review loop
- `.agent/commands/final-review.md` - final review gate
- `.agent/rules/dod.md` - Definition of Done
