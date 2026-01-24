# /sync-docs

Check consistency across PRD, Epic, and implementation.

User-facing output remains in Japanese.

## Usage

```
/sync-docs [prd-file]
```

If omitted, auto-detect the PRD related to the current branch.

## Flow

### Phase 1: Collect inputs

1. Identify PRD file (`docs/prd/*.md`)
2. Identify related Epic file (`docs/epics/*.md`)
3. Collect implementation changes (git diff or specified range)

### Phase 2: Detect diffs

Check diffs from these angles:

- Functional requirements: PRD section 4 vs Epic design / code
- AC: PRD section 5 vs tests / implementation
- Out of scope: PRD Q5 vs implementation scope
- Technical constraints: PRD Q6 vs Epic tech choices

### Phase 3: Classify diffs

- Spec change: PRD requirements changed (action: update PRD)
- Interpretation change: PRD interpretation changed (action: update Epic)
- Implementation-driven: changes due to technical constraints (action: record reason / fix code)

### Phase 4: Output the report

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

## Examples

No diff:

```markdown
## 同期結果

### 差分の種類
（なし）

### 推奨アクション
- [x] 差分なし（同期済み）

### 参照
- PRD: docs/prd/my-project.md
- Epic: docs/epics/my-project-epic.md

### 詳細
PRD、Epic、実装コードは同期されています。
```

Diff exists:

```markdown
## 同期結果

### 差分の種類
- [x] 解釈変更（PRDの解釈が変わる）

### 推奨アクション
- [x] Epic更新が必要

### 影響範囲
- [x] テストへの影響

### 参照（必須）
- PRD: docs/prd/my-project.md セクション 5. AC
- Epic: docs/epics/my-project-epic.md セクション 3.2 API設計
- 該当コード: src/api/handlers.ts:42-58

### 詳細
PRDでは「ユーザー一覧をページネーションで取得」と記載されているが、
実装では無限スクロール方式になっている。

**推奨対応:**
1. Epicの「3.2 API設計」セクションを更新し、無限スクロール方式を明記
2. PRDのACを更新するか、現状維持するか確認
```

## When to run

- When creating a PR: required (DoD)
- After merge: recommended
- During implementation when making a large change: recommended

## Options

- `--verbose`: show detailed diffs
- `--fix`: apply safe auto-fixes (with confirmation)
- `--epic [file]`: check a specific Epic only

## Related

- `.agent/rules/docs-sync.md` - documentation sync rules
- `.agent/rules/dod.md` - Definition of Done

## Notes

- References (PRD/Epic/code) are required; do not omit.
- Do not ignore diffs implicitly.
- Do not modify higher-level docs (PRD) without explicit confirmation.
