# Documentation Sync Rules

Rules to keep PRD, Epic, and implementation code consistent.

---

## Source-of-truth hierarchy

Priority: PRD (requirements) > Epic (implementation plan) > Implementation (code)

Principle: higher-level docs are the source of truth. If there is a contradiction, follow the higher-level doc.

---

## When to sync

- When creating a PR: required (DoD) (reason: detect drift)
- After merge: recommended (reason: confirmation)
- During implementation when making a large change: recommended (reason: early detection)

---

## `/sync-docs` output format

User-facing output remains in Japanese.

```markdown
## 同期結果

### 差分の種類
- [ ] 仕様変更（PRDの要求自体が変わる）
- [ ] 解釈変更（PRDの解釈が変わる）
- [ ] 実装都合（技術的制約による変更）

### 推奨アクション
- [ ] PRD更新が必要
- [ ] Epic更新が必要
- [ ] 実装修正が必要
- [ ] 差分なし（同期済み）

### 影響範囲
- [ ] テストへの影響
- [ ] 運用への影響
- [ ] ユーザーへの影響

### 参照（必須）
- PRD: [ファイル名] セクション [番号/名前]
- Epic: [ファイル名] セクション [番号/名前]
- 該当コード: [ファイル:行]

### 詳細
[差分の具体的な内容]
```

---

## Deterministic inputs and diff source

PRD/Epic resolution and diff source selection are defined in:

- `.agent/commands/sync-docs.md`

Rule: if PRD/Epic or diff source is ambiguous, STOP and ask the user (do not guess).

## How to reference

PRD:

```
PRD: docs/prd/my-project.md セクション 5. AC
```

Epic:

```
Epic: docs/epics/my-project-epic.md セクション 3.2 技術選定
```

Code:

```
該当コード: src/api/handlers.ts:42-58
```

---

## Diff classification rules

Spec change (PRD update required):

- Add/remove/change AC
- Add/remove/change functional requirements
- Change scope

Interpretation change (Epic update required):

- Change tech choices
- Change component architecture
- Change data model

Implementation-driven (fix code or record reason):

- Performance optimization
- Workaround due to library constraints
- Bug fix

Decision sync (when "why" changed):

- 新しい判断を導入した場合は `docs/decisions/` に1決定1ファイルで記録する
- 既存判断を置換する場合は上書きせず、新規Decisionで `Supersedes` を記録する
- `docs/decisions.md` の index と本文ファイルの参照を一致させる

---

## When a diff is found

1. Identify the diff type
2. Provide explicit references (PRD/Epic/code)
3. Provide recommended actions
4. Ask the user to confirm

If a Decision diff exists, include these references explicitly:

- Decision index: `docs/decisions.md`
- Decision body: `docs/decisions/<decision-file>.md`
- Inputs fingerprint source: PRD/Epic/Issue/code reference used in the decision

Forbidden:

- Ignoring the diff implicitly
- Reporting a diff without references
- Changing higher-level docs without explicit confirmation

---

## Related files

- `.agent/commands/sync-docs.md` - sync-docs command
- `.agent/rules/dod.md` - Definition of Done (sync-docs required)
