# /create-prd

Create a PRD (Product Requirements Document).

User-facing interactions and the resulting PRD must be in Japanese.

## Usage

```
/create-prd [project-name]
```

## Flow

### Phase 1: Ask 7 questions (in Japanese)

Ask the user the following questions in order. Provide a good/bad example for each question.
You can reuse the examples embedded in `docs/prd/_template.md`.

```
Q1: 解決したい問題は？
Q2: 誰が使う？
Q3: 何ができるようになる？
Q4: 完成と言える状態は？
Q5: 作らない範囲は？
Q6: 技術的制約は？（選択式）
Q7: 成功指標（測り方）は？
```

### Phase 2: Q6 choice-based constraints

Collect answers using the following choices:

- Existing language/framework fixed
  - Choices: Yes / No / Unknown
  - If Yes: confirm the exact name
- Deployment target fixed
  - Choices: Yes / No / Unknown
  - If Yes: confirm the environment
- Deadline
  - Choices: [date] / Unknown
- Budget cap
  - Choices: ある / ない / Unknown
- PII / confidential data
  - Choices: Yes / No / Unknown
  - If Yes: add security requirements
- Audit log requirement
  - Choices: Yes / No / Unknown
  - If Yes: add audit requirements
- Performance requirement
  - Choices: Yes / No / Unknown
  - If Yes: confirm target operations and rough goals
  - Note: Specific targets and measurement methods are defined in Epic
  - See: `.agent/rules/performance.md` for when this applies
- Availability requirement
  - Choices: Yes / No / Unknown
  - If Yes: confirm uptime requirements and SLA/SLO
  - Note: Specific design and recovery plans are defined in Epic
  - See: `.agent/rules/availability.md` for when this applies

Unknown policy:
- If there are 2+ Unknown items, the PRD is not considered complete
- Unknown items must be confirmed during Epic creation

### Phase 3: Generate the PRD file

1. Copy `docs/prd/_template.md`
2. Fill in the collected answers
3. Save as `docs/prd/[project-name].md`

### Phase 4: Banned vague words check

Ensure the generated PRD does not contain banned vague words (see `docs/prd/_template.md`).
If found:

1. Point out the exact location
2. Suggest a measurable rewrite
3. Ask the user to update the PRD

### Phase 5: Completion checklist

Validate all items:

```
[] Purpose/background is written in 1-3 sentences
[] At least 1 user story exists
[] At least 3 functional requirements are listed
[] At least 3 testable AC items exist
[] At least 1 negative/abnormal AC exists (error/permission/input)
[] Out-of-scope items are explicitly listed
[] No vague expressions remain (banned words)
[] Numbers/conditions are specific
[] Success metrics are measurable
[] Q6 Unknown count is < 2
```

If any item is missing:
1. Identify what is missing
2. Propose concrete additions
3. Ask the user to fill the gaps

### Phase 6: Done

When complete:

1. Output the PRD file path
2. Suggest the next step: `/create-epic`

## Output

```
docs/prd/[project-name].md
```

## Related

- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/rules/dod.md` - Definition of Done

## Next command

After the PRD is complete, run `/create-epic`.
