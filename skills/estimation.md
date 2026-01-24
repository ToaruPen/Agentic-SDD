# Estimation Skill

Create a pre-implementation estimate for an Issue.

This repository requires the Full estimate format (11 sections). Lite mode is not used.

Note: User-facing artifacts remain in Japanese. When you post an estimate to the user,
use the Japanese Full estimate template shown in `.agent/commands/estimation.md`.

---

## Principles

1. Use ranges (e.g. 2-4h, 50-100 LOC)
2. Tie ranges to observed facts (scope, files, tests, similar prior work)
3. Record uncertainty as `Unknown` and ask questions
4. Treat estimates as provisional until Unknowns are resolved
5. Always include confidence (High/Med/Low)

---

## Full estimate (11 sections)

Use the 11-section template in `.agent/commands/estimation.md`.

Rules:

- Fill all sections (no blanks)
- For non-applicable sections, write `N/A (reason)`
- Keep line ranges and file counts within Issue granularity expectations when possible
- If section 10 contains contradictions/Unknowns, stop and ask before implementation

---

## Confidence levels

- High: similar prior work exists; scope is clear (range can be tight)
- Med: some uncertainty; likely within range (range slightly wider)
- Low: high uncertainty / Unknowns remain (double the range or ask questions first)

Low handling:

1. Widen the range (e.g. 2-4h -> 2-8h)
2. Or ask questions to resolve Unknowns and re-estimate

---

## How to justify ranges (examples)

Acceptable rationales (must be specific):

- Similar change history: "a similar API took ~3h"
- Scope/impact: "3 files touched, no new dependencies"
- Test situation: "existing tests cover most paths; add 2 new cases"
- Familiarity: "uses a library already in the repo"

Avoid:

- "seems easy" / "from experience" without evidence

---

## N/A rule

Write `N/A` plus a parenthesized reason.

Examples:

- DB impact: `N/A（DB変更なし）`
- Logging: `N/A（ログ変更なし）`
- I/O list: `N/A（外部I/Oなし）`

---

## After implementation

Compare estimate vs actuals:

- LOC: estimated range vs actual
- Files: estimated vs actual
- Effort: estimated range vs actual

If the gap is large, record why and adjust future estimation heuristics.

---

## Related

- `.agent/commands/estimation.md` - estimation command (Full estimate template)
- `.agent/commands/impl.md` - implementation command (uses `/estimation`)
- `.agent/rules/dod.md` - Definition of Done
- `.agent/rules/issue.md` - Issue granularity rules
