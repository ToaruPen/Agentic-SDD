# /init

Initialize Agentic-SDD in a project.

Important:

- The installation entrypoint is the global `/agentic-sdd` command (helper CLI: `agentic-sdd`).
- This command (`/init`, OpenCode: `/sdd-init`) is a post-install checklist and a safe upgrade guide.

Note: OpenCode has a built-in `/init` (generates AGENTS.md). When generating OpenCode commands,
this command is exposed as `/sdd-init` to avoid conflicts.

User-facing interactions remain in Japanese.

## Usage

```
/init [project-name]
```

## Flow

### Phase 1: Verify current state

1. Confirm you are at the project root (git root).
2. Check whether Agentic-SDD is already installed:
   - `.agent/` exists
   - `docs/prd/_template.md` exists
   - `scripts/agentic-sdd/install-agentic-sdd.sh` exists
3. If not installed:
   - Tell the user to run `/agentic-sdd` (recommended) and STOP.

User-facing message example (Japanese):

```text
このリポジトリにはまだ Agentic-SDD が導入されていません。
まず `/agentic-sdd` を実行して導入してください（導入後に必要なら `/sdd-init` を実行してください）。
```

### Phase 2: Install/upgrade via `/agentic-sdd` (recommended)

Run a dry-run first:

```text
/agentic-sdd --dry-run [tool] [mode]
```

If the command exits with code 2 (conflicts), summarize conflicts and ask whether to re-run with `--force`.

Then install/upgrade:

```text
/agentic-sdd [tool] [mode]
```

Optional (opt-in): install a GitHub Actions CI template:

```text
/agentic-sdd --ci github-actions [tool] [mode]
```

Then edit `.github/workflows/agentic-sdd-ci.yml` and set the 3 required env vars to your project's commands.
Recommended baseline when filling those commands:

- `AGENTIC_SDD_CI_TEST_CMD`: include coverage measurement (and minimum threshold when possible)
- `AGENTIC_SDD_CI_TYPECHECK_CMD`: run in strict mode (for example `tsc --noEmit --strict` / `mypy --strict`)

If needed, also set optional `AGENTIC_SDD_CI_DOCS_CMD` for docs checks.

Notes:

- `mode=minimal`: install workflow files (no GitHub issue/PR templates).
- `mode=full`: also install `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/*`.
- If `AGENTS.md` already exists, the installer will NOT overwrite it. It writes:
  - `AGENTS.md.agentic-sdd.append.md` (manual merge required)

### Phase 3: Tool config sync

If you installed with `--tool none` or you edited `.agent/` after installation, re-generate tool configs:

```bash
# Sync for all tools
./scripts/agentic-sdd/sync-agent-config.sh all
```

OpenCode note: restart OpenCode after sync.

### Phase 3.5: Verify/enable git hooks (required)

Enable the tool-agnostic final gate (pre-commit / pre-push).

Notes:

- The installer attempts to configure this automatically.
- If you are upgrading from an older version, re-run it manually.

```bash
./scripts/agentic-sdd/setup-githooks.sh
```

### Phase 4: Finish

Output a short completion message and next steps (in Japanese), for example:

```text
## 初期化完了

Agentic-SDD の導入が完了しました。

次のステップ:
1. PRD作成: /create-prd [プロジェクト名]
2. 用語集の更新: docs/glossary.md
3. 技術方針の決定: シンプル優先 / バランス
```

## Options

This command is a guide. Installation is performed by `/agentic-sdd`.

Common `/agentic-sdd` options:

- `--mode minimal|full`
- `--tool none|opencode|codex|claude|all`
- `--ci none|github-actions` (opt-in: install a GitHub Actions CI template for tests+coverage/lint/strict-typecheck)
- `--dry-run`
- `--force`
- `--ref <tag>` (install a specific release tag)

## Troubleshooting

### Q: `/agentic-sdd` is not available

Run the global setup once by cloning the Agentic-SDD repo and running:

```bash
./scripts/setup-global-agentic-sdd.sh
```

Alternative (without global setup): clone the Agentic-SDD repo and run the installer directly:

```bash
./scripts/install-agentic-sdd.sh --target <project-dir> --mode minimal
```

### Q: `AGENTS.md` already exists

A: This is expected. The installer writes `AGENTS.md.agentic-sdd.append.md` instead of overwriting.
Manually merge it into your existing `AGENTS.md`.

## Related

- `AGENTS.md` - AI agent rules
- `README.md` - overview
- `.agent/rules/` - rules

## Next command

After init, run `/create-prd`.
