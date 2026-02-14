# UI Redesign Skill

Guidelines for iterative UI redesign with measurable visual feedback.

This skill is framework-agnostic and optimized for short "design -> verify" loops.

---

## Overview

Use this when you need to improve an existing UI (not build from scratch), especially when:

- usability issues are visible in screenshots
- state messaging and operability are inconsistent
- layout hierarchy is unclear
- the team wants deterministic evidence per round

---

## Principles

1. **State honesty first**
   - Visual state must match actual operability (disabled means not operable, errors mean degraded mode).

2. **Action clarity over decoration**
   - Primary action should be obvious and never obscure critical content.

3. **Progressive disclosure**
   - Hide debug/internal metadata in normal user mode.

4. **One round, small scope**
   - Limit each round to 1-3 highest-impact issues.

5. **Evidence-driven decisions**
   - Every round needs screenshots + test results.

---

## Patterns

### 1) State matrix before styling

Define UI states explicitly before changing visuals.

For each state, specify:

- CTA label
- CTA enabled/disabled
- helper/error text
- major visual emphasis

### 2) Hero vs controls separation

When there is hero content (avatar/video/canvas/chart):

- keep hero area visually clean
- place controls in a separate band/panel
- avoid large controls floating over core content

### 3) Debug visibility guard

Use explicit conditions for debug elements:

- dev-only (`import.meta.env.DEV`, `NODE_ENV`, etc.)
- or runtime flag

Never expose internal status labels by default in user-facing mode.

### 4) Screenshot rounds

Per round:

1. baseline screenshot(s)
2. patch
3. verification (`typecheck/lint/test` and runtime checks when needed)
4. new screenshot(s)
5. compare and record delta

Store screenshots under a stable path convention:

```
var/screenshot/issue-<n>/round-<xx>/
```

### 5) Responsive pass

Always validate at least:

- desktop (e.g. 1280x720)
- mobile (e.g. 390x844)

Check touch target size, overlap, clipping, and scroll traps.

---

## Checklist

### Usability

- [ ] Error/connection states do not imply false operability
- [ ] Primary action remains reachable in desktop/mobile
- [ ] No critical content is blocked by CTA overlays

### Readability

- [ ] Heading/body/assistive text hierarchy is clear
- [ ] Important messages are visible without crowding
- [ ] Label wording is short and consistent

### Visual structure

- [ ] Hero area and control area are intentionally separated
- [ ] Spacing scale is consistent (no accidental jumps)
- [ ] Color emphasis aligns with interaction priority

### Technical verification

- [ ] Project standard `typecheck` passes
- [ ] Project standard `lint` passes
- [ ] Project standard `test` passes
- [ ] Runtime smoke/E2E is run when behavior changes

### Evidence

- [ ] Baseline and latest screenshots are saved
- [ ] Round-by-round decisions are documented briefly

---

## Anti-patterns

- Fixing multiple unrelated screens in one round
- Styling first without a state matrix
- Keeping contradictory signals (error shown but CTA appears fully active)
- Chasing purely subjective pixel tweaks before usability fixes
- Claiming improvement without screenshots/tests

---

## Related

- `.agent/commands/ui-iterate.md` - UI iterative redesign flow
- `skills/crud-screen.md` - screen design checklist
- `skills/testing.md` - test strategy and coverage
- `.agent/commands/review-cycle.md` - local review loop
- `.agent/commands/final-review.md` - final gate
