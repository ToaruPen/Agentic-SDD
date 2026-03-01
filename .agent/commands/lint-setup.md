# /lint-setup

Detect repository languages and produce lint setup recommendations, then let the agent configure based on official documentation and user preference.

This is an independent command that can be run standalone or invoked from `/generate-project-config`.

User-facing output remains in Japanese.

## Usage

```
/lint-setup [options]
```

## Options

- `--path <dir>`: target directory (default: project root)
- `--json`: output recommendation results in JSON format

## Flow

### Phase 1: Language and subproject detection

1. Run `scripts/detect-languages.py --path <dir> --json` to detect:
   - Languages from manifest files (pyproject.toml, package.json, go.mod, Cargo.toml, etc.)
   - Existing linter configurations (.eslintrc*, ruff.toml, biome.json, etc.)
   - Monorepo structure (multiple languages in subdirectories)
2. If no language is detected, STOP with error:

```text
[ERROR] 言語を検出できませんでした。
マニフェストファイル（pyproject.toml, package.json, go.mod 等）が存在するか確認してください。
```

### Phase 2: Existing linter configuration check

1. If existing linter configs are detected:
   - List detected configs
   - Do NOT overwrite automatically
   - Record existing configs in the evidence trail
2. If multiple conflicting tools are detected for the same purpose (e.g., ESLint + Biome,
   ruff + flake8), continue with recommendations but mark conflicts explicitly for user decision.

```text
[WARN] 複数の競合する lint ツール設定を検出しました。推奨を出力し、最終適用方針はユーザー確認が必要です。
```

### Phase 3: Registry lookup

1. Load `scripts/lint-registry.json` to determine the recommended toolchain for each detected language:
   - Linter (e.g., ruff for Python, ESLint for TypeScript)
   - Formatter (e.g., ruff format for Python, Prettier for TypeScript)
   - Type checker (e.g., mypy for Python, tsc for TypeScript)
2. Treat `essential_rules` / `recommended_rules` / `framework_rules` as HINTS for agent interpretation,
   not rigid categories.
3. For unknown languages not in the registry, skip with a warning (do not fail):

```text
[WARN] レジストリに未登録の言語を検出: [language]。手動での lint 設定が必要です。
```

### Phase 3.5: User preference interview (QuestionTool)

1. Before generating any configuration files, the agent MUST ask the user via QuestionTool:

```text
どのようなlint設定を希望しますか？（例: 厳しめ、最低限、セキュリティ重視 等）
```

2. The response is required input for Phase 5.
3. If no user preference is obtained, STOP and do not generate config files.

### Phase 4: Official documentation reference (REQUIRED)

This phase is mandatory - not optional.

For each detected language/linter combination, the agent MUST:

1. Load the `skills/linter-setup.md` skill for research guidance
2. Fetch the official documentation URL from `lint-registry.json` (`docs_url` field)
3. Use `librarian` or `webfetch` to retrieve the latest rules/configuration from the official docs
4. Interpret rule guidance using user preference + official docs + registry hints:
   - Baseline rules that should always be enabled when applicable
   - Additional strictness/security/style rules based on user preference
   - Framework-specific rules for detected frameworks (Django, FastAPI, React, etc.)
5. Check for formatter conflicts using the official docs

Fail-fast: If official documentation cannot be fetched, STOP with error:

```text
[ERROR] 公式ドキュメントを取得できませんでした: [url]
ネットワーク接続を確認してください。フォールバックなしで停止します。
```

### Phase 5: Agent-driven configuration generation

1. Run `scripts/lint-setup.py --path <dir> --json` to get recommendation data (input for the agent).
2. The script only outputs recommendations and never generates config files.
3. The agent is responsible for generating/updating configuration files by combining:
   - User preference from Phase 3.5
   - Latest official documentation research from Phase 4
   - Registry recommendations from Phase 3
4. Expected script output schema:

```json
{"languages": [...], "recommendations": [{"language": "...", "linter": {"name": "...", "docs_url": "...", "config_file": "...", "essential_rules": [...], "recommended_rules": [...], "ci_command": "..."}, "formatter": {...}, "type_checker": {...}, "framework_rules": {...}}], "ci_commands": [...], "existing_configs": [...], "conflicts": [...]}
```

5. User-facing output example:

```text
推奨CIコマンド:
  AGENTIC_SDD_CI_LINT_CMD: ruff check .
  AGENTIC_SDD_CI_FORMAT_CMD: ruff format --check .
  AGENTIC_SDD_CI_TYPECHECK_CMD: mypy --strict .
```

### Phase 6: Evidence trail

Record the following in `.agentic-sdd/project/rules/lint.md`:

- Reference URLs accessed and retrieval timestamps
- Detected languages and sources
- User preference captured in Phase 3.5
- Selected linter toolchain and rationale
- How official docs and registry hints were interpreted
- Formatter conflict decisions
- Generated/updated file list

Use the template: `templates/project-config/rules/lint.md.j2`

For evidence-only verification runs, `--dry-run` is allowed only to inspect/record outputs without file writes.

## Monorepo handling

When `is_monorepo: true` is detected:

1. If 2+ languages with independent subprojects:
   - Produce per-subproject recommendations
   - Generate configs only after Phase 3.5 preference capture + Phase 4 doc validation for each subproject
2. If single language with multiple subprojects:
   - Generate root-level config (shared across subprojects) only after the same gates

## Fail-fast conditions

| Condition | Action |
|-----------|--------|
| No language detected | STOP with error |
| Official docs fetch failed | STOP with error (no fallback) |
| `--path` directory does not exist | STOP with error |
| User preference not captured in Phase 3.5 | STOP with error |
| Unknown language (not in registry) | WARN and skip that language |
| Conflicting lint tools detected | WARN + require explicit user decision before applying conflicting changes |
| Existing linter config exists | WARN + require explicit user decision before modifying existing config |

## Graduation strategy (new vs existing projects)

- **New project** (no existing linter configs): Apply baseline + preference-aligned rules from official docs
- **Existing project** (has code but no linter): Start with conservative baseline, then expand according to user preference
- **Existing project with linter**: Keep current behavior by default; apply only user-approved incremental changes with evidence

## Related

- `scripts/detect-languages.py` - language detection script
- `scripts/lint-registry.json` - language-to-linter recommendation registry
- `scripts/lint-setup.py` - recommendation output script (`--json`)
- `skills/linter-setup.md` - agent research guidance
- `.agent/commands/generate-project-config.md` - calls `/lint-setup` optionally
- `.agent/commands/init.md` - references `/lint-setup` in completion steps

## Next command

After lint setup, continue with `/create-issues` or `/impl` as needed.
