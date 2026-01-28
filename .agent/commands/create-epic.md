# /create-epic

Create an Epic (implementation plan) from a PRD.

The generated Epic document remains in Japanese (use `docs/epics/_template.md`).

## Usage

```
/create-epic [prd-file]
```

## Flow

### Phase 1: Read the PRD

1. Read the specified PRD file
2. Re-check the PRD completion checklist
3. Extract Q6 items that are `Unknown`

### Phase 2: Resolve Unknown items

Before creating the Epic, ask the user (in Japanese) to resolve each `Unknown` item.
If 2+ Unknown items exist in Q6, the PRD is not complete and you must stop.

### Phase 3: Apply the technical policy constraints

Use PRD section 7 (scale/policy) and PRD Q6 constraints to apply limits.

Simple-first:

- External services: max 1
- New libraries: max 3
- New components: max 3
- Async infrastructure: forbidden
- Microservices: forbidden
- Container orchestration: forbidden

Balanced:

- External services: max 3
- New libraries: max 5
- New components: max 5
- Async infrastructure: allowed with explicit reason
- Microservices: allowed with explicit reason

### Phase 4: Create the 3 required lists

Always include these three lists in the Epic (write "なし" if not applicable):

- External services
- Components
- New tech

### Phase 4.5: Project-specific metrics (recommended)

If the project has measurable success criteria (performance/accuracy/etc), fill
section 3.5 in `docs/epics/_template.md`.

### Phase 4.6: Production quality sections (conditional)

Based on PRD Q6 answers, include the required production quality sections in section 5:

- **Q6-5: PII/confidential data = Yes** → 5.2 Security design (see `.agent/rules/security.md`)
- **Q6-6: Audit log requirement = Yes** → 5.3 Observability design (see `.agent/rules/observability.md`)
- **Q6-7: Performance requirement = Yes** → 5.1 Performance design (see `.agent/rules/performance.md`)
- **Q6-8: Availability requirement = Yes** → 5.4 Availability design (see `.agent/rules/availability.md`)

Rules:
- If Q6 is "Yes": fill the section with specific details
- If Q6 is "No": write "N/A（理由）" in the section
- If Q6 is "Unknown": resolve Unknown first (Phase 2)

### Phase 5: Apply counting definitions

- External services: each SaaS / managed DB / identity provider / external API counts as 1
- Components: each deployable unit (process/job/worker/batch) counts as 1
- New tech: each major category (DB/queue/auth/observability/framework/cloud service) counts as 1

### Phase 6: Provide simpler alternatives

If a simpler alternative exists, present both options and record the chosen option and the reason
in the Epic (follow the template's "技術選定" section style).

### Phase 7: Create an Issue split proposal

Split Issues following `.agent/rules/issue.md`:

- LOC: 50-300
- Files: 1-5
- AC: 2-5

### Phase 8: Validation checklist

```
[] New tech/service names <= 5
[] New component count is within the policy limit
[] Every choice has a reason
[] Simpler alternative(s) are presented when applicable
[] No item is justified only by "for future extensibility"
[] The 3 required lists are present
```

### Phase 9: Generate the Epic

1. Copy `docs/epics/_template.md`
2. Fill in the collected information
3. Save as `docs/epics/[prd-name]-epic.md`

## Output

```
docs/epics/[prd-name]-epic.md
```

## Prohibited

- Adding complexity justified only by "for future extensibility"
- Proposing microservices under Simple-first
- Omitting the 3 required lists
- Making a tech choice without presenting a simpler alternative (when one exists)

## Related

- `.agent/rules/epic.md` - epic generation rules
- `.agent/rules/issue.md` - issue granularity rules
- `.agent/rules/docs-sync.md` - documentation sync rules

## Next command

After the Epic is complete:

1. (Optional) Run `/generate-project-config` to generate project-specific skills/rules
   - Generates files based on tech stack and Q6 requirements
   - Output: `.agentic-sdd/project/` directory
2. Run `/create-issues` to split the Epic into Issues
