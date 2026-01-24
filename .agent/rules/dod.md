# Definition of Done (DoD)

Criteria for considering work "done" (Issue / PR / Epic / PRD).

---

## Issue done

Required:

- [ ] All AC are satisfied
- [ ] Tests are added/updated (when applicable)
- [ ] `/sync-docs` is "no diff" or the diff is explicitly approved
- [ ] Code review is complete
- [ ] CI passes (when applicable)

Optional:

- [ ] Documentation updated
- [ ] Performance is acceptable
- [ ] Security considerations reviewed

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

---

## Related

- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/commands/sync-docs.md` - sync-docs command
- `.agent/commands/review.md` - review command
- `skills/estimation.md` - estimation skill
