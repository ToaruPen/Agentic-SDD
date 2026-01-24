# /init

Initialize the Agentic-SDD workflow files in a project.

Note: OpenCode has a built-in `/init` (generates AGENTS.md). When generating OpenCode commands,
this command is exposed as `/sdd-init` to avoid conflicts.

User-facing interactions remain in Japanese.

## Usage

```
/init [project-name]
```

## Flow

### Phase 1: Collect project info (ask in Japanese)

```text
プロジェクトを初期化します。以下の質問に答えてください。

1. プロジェクト名は？
2. このプロジェクトは新規ですか、既存ですか？
3. 使用するプログラミング言語/フレームワークは？（決まっていない場合は「未定」）
4. GitHubリポジトリは既にありますか？
```

### Phase 2: Confirm the existing structure (existing projects)

```text
現在のディレクトリ構造:
[構造を表示]

Agentic-SDDのファイルを追加しますか？
- .agent/ ディレクトリ
- docs/ ディレクトリ（既存の場合はマージ）
- AGENTS.md
```

### Phase 3: Install files

Create these directories/files (mode-dependent):

- `.agent/` (commands, rules, agents, schemas)
- `docs/` (`prd/_template.md`, `epics/_template.md`, `decisions.md`, `glossary.md`)
- `skills/` (design skills)
- `scripts/` (install/sync/review-cycle helpers)
- `AGENTS.md`

### Phase 4: Merge with existing files

If `docs/` already exists:

- Keep existing files
- Add `docs/prd/` and `docs/epics/` subdirectories
- Add `_template.md` files

If `AGENTS.md` already exists:

- Create a backup (`AGENTS.md.bak`)
- Overwrite or ask for a manual merge

### Phase 5: Update `.gitignore`

Add (as needed):

```
# Agentic-SDD
.agent/agents/*.local.md
.agentic-sdd/
.opencode/
.codex/
```

### Phase 6: Finish

Output a short completion message and next steps (in Japanese), for example:

```text
## 初期化完了

Agentic-SDDのセットアップが完了しました。

次のステップ:
1. PRD作成: /create-prd [プロジェクト名]
2. 用語集の更新: docs/glossary.md
3. 技術方針の決定: シンプル優先 / バランス / 拡張性優先
```

## Options

- `--force`: overwrite existing files (no prompts)
- `--dry-run`: preview only
- `--minimal`: install minimal set only (exclude `skills/`)

## Applying to an existing project

Suggested gradual migration:

```text
Week 1: use /create-prd only
Week 2: add /create-epic
Week 3: add /create-issues
Week 4: use the full workflow
```

## Troubleshooting

### Q: Conflicts with existing docs/

A: `docs/prd/` and `docs/epics/` are subdirectories and typically do not conflict.

### Q: AGENTS.md already exists

A: Use `--dry-run` and manually merge if needed.

### Q: Team usage

A: Commit these to the repository:

- `.agent/`
- `docs/prd/_template.md`, `docs/epics/_template.md`, `docs/decisions.md`, `docs/glossary.md`
- `skills/`
- `scripts/`
- `.gitignore` (if updated)
- `AGENTS.md`

## Related

- `AGENTS.md` - AI agent rules
- `README.md` - overview
- `.agent/rules/` - rules

## Next command

After init, run `/create-prd`.
