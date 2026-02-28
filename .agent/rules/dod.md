# Definition of Done (DoD)

Criteria for considering work "done" (Issue / PR / Epic / PRD).

---

## Issue done

Required:

- [ ] All AC are satisfied
- [ ] Tests are added/updated (when applicable)
- [ ] Quality checks are run and passing (tests required; lint/format/typecheck required). If a required check does not exist yet, introduce the minimal viable check before proceeding. If a required check cannot be run, record "not run: reason" and get explicit approval.
- [ ] `/sync-docs` is "no diff" or the diff is explicitly approved
- [ ] 重要な判断（why）を追加/変更した場合、Decision Snapshot が `docs/decisions/` に追記され、`docs/decisions.md` の index が更新されている（`python3 scripts/validate-decision-index.py` で検証。`/create-pr` 前に必須実行）
- [ ] Code review is complete
- [ ] CI passes (when applicable)

CI note:
- If you choose to enforce CI, require it via branch protection (required status checks).
- Agentic-SDD can install a GitHub Actions CI template with `/agentic-sdd --ci github-actions` (opt-in).

Optional (promote to Required based on PRD Q6):

- [ ] Documentation updated
- [ ] Performance is acceptable (→ Required if Q6-7: Yes, see `.agent/rules/performance.md`)
- [ ] Security considerations reviewed (→ Required if Q6-5: Yes, see `.agent/rules/security.md`)
- [ ] Observability implemented (→ Required if Q6-6: Yes, see `.agent/rules/observability.md`)
- [ ] Availability requirements met (→ Required if Q6-8: Yes, see `.agent/rules/availability.md`)

---

## PR done

Required:

- AC: all Issue AC are satisfied
- sync-docs: run `/sync-docs` and assess drift
- Tests: new/changed code is covered
- Review: at least one approval

How to handle sync-docs result:

- No diff: ready to merge
- Diff (minor): record the diff and merge
- Diff (major): update PRD/Epic before merging

---

## Epic done

- [ ] All related Issues are closed
- [ ] The 3 required lists are up-to-date
- [ ] Consistency with PRD is confirmed

---

## PRD done

All completion checklist items in `docs/prd/_template.md` are satisfied:

- [ ] Purpose/background written in 1-3 sentences
- [ ] At least 1 user story exists
- [ ] At least 3 functional requirements are listed
- [ ] At least 3 testable AC items exist
- [ ] At least 1 negative/abnormal AC exists
- [ ] Out of scope is explicitly listed
- [ ] No vague expressions remain
- [ ] Numbers/conditions are specific
- [ ] Success metrics are measurable
- [ ] Q6 Unknown count is < 2

---

## Estimate done

Full estimate (11 sections) is fully written:

```
0. Preconditions
1. Interpretation
2. Change targets (file:line)
3. Tasks and effort (range + confidence)
4. DB impact            <- write reason when N/A
5. Logging              <- write reason when N/A
6. I/O list              <- write reason when N/A
7. Refactor candidates   <- write reason when N/A
8. Phasing               <- write reason when N/A
9. Test plan
10. Contradictions/unknowns/questions
11. Out of scope (will not change)
```

In addition:

- The estimate is reviewed with the user and explicitly approved before implementation starts.

Implementation note:

- Use `/estimation` to create the Full estimate and run the approval gate.

---

## Evidence requirements

Claims require corresponding evidence:

- Bug fixed: Test that transitions from fail to pass
- Performance improved: Before/After numbers with measurement method
- Feature added: Tests satisfying AC + behavior confirmation
- Refactored: All existing tests pass + explanation of changes

Not acceptable: AI report of "Fixed" or "Improved" alone (unverifiable)

### Before/After recording

For each change, record:
- Before: State before change (test results, logs, numbers)
- After: State after change
- Diff: Concrete observable change

This ensures changes are verifiable and not based on hope.

---

## Related

- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/commands/sync-docs.md` - sync-docs command
- `.agent/commands/final-review.md` - final review command
- `.agent/commands/estimation.md` - Full estimate + approval gate
- `skills/estimation.md` - estimation skill
- `.agent/rules/impl-gate.md` - implementation gate checklist

Production quality rules (Optional → Required based on PRD Q6):

- `.agent/rules/performance.md` - Performance rules (Q6-7)
- `.agent/rules/security.md` - Security rules (Q6-5)
- `.agent/rules/observability.md` - Observability rules (Q6-6)
- `.agent/rules/availability.md` - Availability rules (Q6-8)
