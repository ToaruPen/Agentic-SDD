# /lint-setup

Detect repository languages and configure recommended linters using official documentation.

This is an independent command that can be run standalone or invoked from `/generate-project-config`.

User-facing output remains in Japanese.

## Usage

```
/lint-setup [options]
```

## Options

- `--path <dir>`: target directory (default: project root)
- `--dry-run`: preview generated files without writing
- `--json`: output results in JSON format

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
   - Do NOT overwrite — generate a diff proposal only
   - Record existing configs in the evidence trail
2. If multiple conflicting tools are detected for the same purpose (e.g., ESLint + Biome,
   ruff + flake8), downgrade to **proposal mode**:

```text
[WARN] 複数の競合する linter 設定を検出しました。自動生成を中断し、提案のみ出力します。
```

### Phase 3: Registry lookup

1. Load `scripts/lint-registry.json` to determine the recommended toolchain for each detected language:
   - Linter (e.g., ruff for Python, ESLint for TypeScript)
   - Formatter (e.g., ruff format for Python, Prettier for TypeScript)
   - Type checker (e.g., mypy for Python, tsc for TypeScript)
2. For unknown languages not in the registry, skip with a warning (do not fail):

```text
[WARN] レジストリに未登録の言語を検出: [language]。手動での linter 設定が必要です。
```

### Phase 4: Official documentation reference (REQUIRED)

This phase is mandatory — not optional.

For each detected language/linter combination, the agent MUST:

1. Load the `skills/linter-setup.md` skill for research guidance
2. Fetch the official documentation URL from `lint-registry.json` (`docs_url` field)
3. Use `librarian` or `webfetch` to retrieve the latest rules/configuration from the official docs
4. Determine recommended rule sets based on the skill's classification criteria:
   - **Essential**: rules that should always be enabled
   - **Recommended**: rules that improve quality but may need project-specific tuning
   - **Framework-specific**: rules for detected frameworks (Django, FastAPI, React, etc.)
5. Check for formatter conflicts using the official docs

Fail-fast: If official documentation cannot be fetched, STOP with error:

```text
[ERROR] 公式ドキュメントを取得できませんでした: [url]
ネットワーク接続を確認してください。フォールバックなしで停止します。
```

### Phase 5: Configuration file generation

1. Run `scripts/lint-setup.py` with the detection results and researched rules to generate:
   - Linter configuration files (e.g., `pyproject.toml` `[tool.ruff]` section, `eslint.config.js`)
   - CI recommended commands:
     ```text
     推奨CIコマンド:
       AGENTIC_SDD_CI_LINT_CMD: ruff check .
       AGENTIC_SDD_CI_FORMAT_CMD: ruff format --check .
       AGENTIC_SDD_CI_TYPECHECK_CMD: mypy --strict .
     ```
2. If existing linter config exists, output diff proposal instead of generating files
3. If `--dry-run`, display what would be generated without writing

### Phase 6: Evidence trail

Record the following in `.agentic-sdd/project/rules/lint.md`:

- Reference URLs accessed and retrieval timestamps
- Detected languages and sources
- Selected linter toolchain and rationale
- Rule classification decisions (Essential/Recommended/Framework-specific)
- Formatter conflict decisions
- Generated file list

Use the template: `templates/project-config/rules/lint.md.j2`

## Monorepo handling

When `is_monorepo: true` is detected:

1. If 2+ languages with independent subprojects:
   - Downgrade to **proposal mode** (do not auto-generate root-level configs)
   - Output per-subproject recommendations
2. If single language with multiple subprojects:
   - Generate root-level config (shared across subprojects)

## Fail-fast conditions

| Condition | Action |
|-----------|--------|
| No language detected | STOP with error |
| Official docs fetch failed | STOP with error (no fallback) |
| Unknown language (not in registry) | WARN and skip that language |
| Multiple conflicting linters detected | Downgrade to proposal mode |
| Existing linter config exists | Diff proposal only (no overwrite) |
| `--path` directory does not exist | STOP with error |

## Graduation strategy (new vs existing projects)

- **New project** (no existing linter configs): Apply Essential + Recommended rules
- **Existing project** (has code but no linter): Apply Essential rules only, recommend gradual expansion
- **Existing project with linter**: Diff proposal only

## Related

- `scripts/detect-languages.py` — language detection script
- `scripts/lint-registry.json` — language-to-linter mapping
- `scripts/lint-setup.py` — configuration generation script
- `skills/linter-setup.md` — agent research guidance
- `.agent/commands/generate-project-config.md` — calls `/lint-setup` optionally
- `.agent/commands/init.md` — references `/lint-setup` in completion steps

## Next command

After lint setup, continue with `/create-issues` or `/impl` as needed.
