# Epic Generation Rules

Rules that constrain Epic generation to prevent overreach and keep designs simple.

---

## 3-layer structure

- Layer 1: PRD constraints (scale, technical policy, fixed constraints)
- Layer 2: AI rules (counting definitions, allow/deny lists)
- Layer 3: Review checklist

---

## Layer 1: PRD constraints

Carry over from PRD:

- Scale: PRD section 7
- Technical policy: PRD section 7
- Fixed constraints: PRD Q6

---

## Layer 2: AI rules

### Counting definitions

- External services
  - Definition: separately managed services used over the network
  - Unit: each SaaS / managed DB / identity provider / external API counts as 1
- Components
  - Definition: deployable unit
  - Unit: each process / job / worker / batch counts as 1
- New tech
  - Definition: major technology category newly introduced
  - Unit: each DB / queue / auth / observability / framework / cloud service counts as 1

### Allow/deny lists

Simple-first:

- External services: max 1 (e.g. DB only)
- New libraries: max 3
- New components: max 3
- Async infrastructure (queue/event stream): forbidden
- Microservices: forbidden
- Container orchestration (K8s etc): forbidden

Balanced:

- External services: max 3
- New libraries: max 5
- New components: max 5
- Async infrastructure: allowed with explicit reason
- Microservices: allowed with explicit reason

Extensibility-first:

- No hard limits, but every choice requires a reason

### Exception condition

Exceed limits only when the PRD explicitly requires it.

Examples:

- PRD: "リアルタイム通知が必須" -> allow WebSocket/async
- PRD: "認証は既存IdPを使用" -> allow external IdP

---

## Layer 3: Review checklist

New-tech counting:

- Count only newly introduced/proposed tech/service names
- Do not count tech already used in the project

Checklist:

```
[] New tech/service names <= 5
[] New component count is within policy limit
[] Every choice has a reason
[] Simpler alternative(s) are presented when applicable
[] No item is justified only by "for future extensibility"
[] The 3 required lists are present
```

---

## Required artifacts (3 lists)

Every Epic must include these lists (write "なし" if not applicable):

- External services list
- Components list
- New tech list

---

## Generation rules

1. If a simpler alternative exists, present both
2. Under Simple-first, prefer a monolithic design
3. Do not add complexity justified only by "for future extensibility"

---

## If rules are violated

1. Point out the violation
2. Propose a simpler alternative
3. Ask the user to choose

---

## Related

- `.agent/commands/create-epic.md` - create-epic command
- `docs/epics/_template.md` - Epic template
- `.agent/rules/issue.md` - Issue granularity rules
