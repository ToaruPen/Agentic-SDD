# Performance Rules

Rules for projects with performance requirements.

Applies when: PRD Q6-7 (Performance requirement) is "Yes"

---

## Required when

<!-- grep keyword: PERFORMANCE_REQUIRED_WHEN -->

Apply this rule if any of the following conditions are met:

- [ ] Users wait interactively for operations (search, list display, form submission)
- [ ] 10+ concurrent users are expected
- [ ] Processing volume exceeds 1000 items/day
- [ ] SLA/contract specifies response time requirements
- [ ] Resource constraints exist (mobile, embedded, edge devices)
- [ ] Competing with alternatives where slowness leads to rejection

---

## Not required when

<!-- grep keyword: PERFORMANCE_NOT_REQUIRED_WHEN -->

Not applicable in these cases:

- Internal tools (few users, can wait)
- Low-frequency operations (a few times per year)
- Prototype/PoC (purpose is to validate functionality)
- Batch processing (loose time constraints, overnight completion is acceptable)

---

## PRD requirements

<!-- grep keyword: PERFORMANCE_PRD_REQ -->

When PRD Q6-7 is "Yes", include:

1. Target operations overview (e.g., search, list display)
2. Rough goals (e.g., "search within a few seconds")

Specific targets and measurement methods are defined in Epic.

---

## Epic requirements

<!-- grep keyword: PERFORMANCE_EPIC_REQ -->

Include the following section in Epic:

<epic_section name="Performance Design">

### Performance Design (Required if PRD Q6-7: Yes)

Target operations:
- [Operation]: [Target]
- Example: Search: response within 3 seconds
- Example: List display: initial render within 2 seconds

Measurement method:
- Tool: [e.g., k6, Artillery, Lighthouse, browser DevTools]
- Environment: [e.g., staging, production-equivalent data volume]
- Conditions: [e.g., 100 concurrent users, 1000 records]

Bottleneck candidates:
- [Candidate]: [Reason]
- Example: DB query: potential N+1
- Example: External API: unknown response time

Mitigation strategy:
- [Strategy]: [Overview]
- Example: Add index, introduce caching, async processing

</epic_section>

---

## DoD requirements

<!-- grep keyword: PERFORMANCE_DOD_REQ -->

The following become required in DoD (when Q6-7: Yes):

- [ ] Performance targets are met
- [ ] Before/After measurements are recorded
- [ ] Measurement method is documented

---

## Evidence format

<!-- grep keyword: PERFORMANCE_EVIDENCE -->

Performance improvement reports must include:

```
Before: [value] ([measurement method])
After: [value] ([measurement method])
Target: [target value]
Result: Achieved / Not achieved (reason)
```

<example type="good">
Before: Search response 8.2s (k6, 100 concurrent users, staging)
After: Search response 1.8s (same conditions)
Target: Within 3 seconds
Result: Achieved
</example>

<example type="bad">
Performance was improved.
(No numbers, no measurement method, no comparison)
</example>

---

## Checklist

<!-- grep keyword: PERFORMANCE_CHECKLIST -->

### Design phase

- [ ] Target values are defined numerically in Epic
- [ ] Measurement method is decided
- [ ] Measurement environment is clear (staging/production-equivalent)
- [ ] Bottleneck candidates are identified

### Implementation phase

- [ ] Before measurement is recorded
- [ ] After measurement is recorded
- [ ] Target is met (or reason is explained)

### Review phase

- [ ] Before/After numbers are presented as evidence
- [ ] Measurement conditions are reproducible

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `skills/testing.md` - Test strategy
- `docs/prd/_template.md` - PRD Q6-7
