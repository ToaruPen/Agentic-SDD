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

- PRD (Japanese requirement text): "リアルタイム通知が必須" -> allow WebSocket/async
- PRD (Japanese requirement text): "認証は既存IdPを使用" -> allow external IdP

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
[] Project-optimized folder structure design is present
[] Scoped `AGENTS.md` map placement plan is present
[] Modern fast lint/format/typecheck (+coverage) toolchain choice is present with rationale and local/CI integration points
```

---

## Required artifacts (3 lists)

Every Epic must include these lists (write `なし` (Japanese for "none") if not applicable):

- External services list
- Components list
- New tech list

## Required architecture and quality addenda (mandatory)

Every Epic must also include the following mandatory addenda:

- Folder structure design
  - Design an explicit, project-optimized directory layout.
  - Explain the role and ownership boundary of each top-level directory.
- Scoped `AGENTS.md` map plan
  - Define where root/scoped `AGENTS.md` files live.
  - Use `AGENTS.md` as a concise map with links to deeper docs (progressive disclosure).
- Lint/format/typecheck (+coverage) toolchain decision
  - Select modern, fast, maintained tools suitable for the target language stack.
  - Record rationale (speed, maintenance, adoption, compatibility), one simpler alternative,
    local/CI integration plan, strict typecheck mode, and coverage measurement policy.

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

## Q6 → Epic section mapping

Based on PRD Q6 answers, additional Epic sections become required.

<!-- grep keyword: EPIC_Q6_MAPPING -->

| PRD Q6 item | Answer | Required Epic section | Rule file |
|-----------|------|-------------------|---------------|
| `Q6-5: 個人情報/機密データ` | Yes | 5.2 セキュリティ設計 | `.agent/rules/security.md` |
| `Q6-6: 監査ログ要件` | Yes | 5.3 観測性設計 | `.agent/rules/observability.md` |
| `Q6-7: パフォーマンス要件` | Yes | 5.1 パフォーマンス設計 | `.agent/rules/performance.md` |
| `Q6-8: 可用性要件` | Yes | 5.4 可用性設計 | `.agent/rules/availability.md` |

Apply rules:

- If Q6 is `Yes`: fill the mapped section with specific details (required)
- If Q6 is `No`: write `N/A（理由）` (Japanese; "N/A (reason)") in the mapped section
- If Q6 is `Unknown`: resolve Unknown first, then fill the section

DoD linkage:

- If Q6 is `Yes`, the corresponding DoD items are promoted from Optional to Required.
- See `.agent/rules/dod.md` for details.

---

## Related

- `.agent/commands/create-epic.md` - create-epic command
- `docs/epics/_template.md` - Epic template
- `.agent/rules/issue.md` - Issue granularity rules
- `.agent/rules/performance.md` - Performance rules
- `.agent/rules/security.md` - Security rules
- `.agent/rules/observability.md` - Observability rules
- `.agent/rules/availability.md` - Availability rules
