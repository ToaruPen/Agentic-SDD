# Linter Setup Skill

Guide for researching and configuring linters during `/lint-setup` execution.

This skill defines the agent's research procedure, rule classification criteria,
and official documentation URLs for each supported language.

---

## Research procedure

When `/lint-setup` Phase 4 runs, follow these steps for each detected language:

1. **Receive user preference** from `どのようなlint設定を希望しますか？`
2. **Identify the recommended toolchain** from `scripts/lint-registry.json`
3. **Fetch the official documentation** using `webfetch` or `librarian`:
   - Use the `docs_url` from the registry entry
   - Fetch the rules/configuration reference page
4. **Interpret preference and classify/select rules** into Essential / Recommended / Framework-specific (see criteria below)
5. **Generate configuration based on user preference and official documentation**
6. **Check formatter conflicts** against the generated configuration using official conflict documentation

---

## User preference interpretation

Treat `essential_rules` / `recommended_rules` in `scripts/lint-registry.json` as
REFERENCE HINTS, not rigid categories. Final configuration must be decided from:

1. user preference intent
2. official tool documentation
3. project context (new vs existing codebase, framework presence)

Preference mapping guide:

- `厳しめ` / `strict`
  - Enable all Essential + Recommended rules
  - Add strict/pedantic presets where available (`@typescript-eslint/strict`, `clippy::pedantic`, etc.)
- `最低限` / `minimal`
  - Enable Essential rules only
  - Prefer warning mode for initial rollout in existing projects
- `セキュリティ重視` / `security-focused`
  - Prioritize security-focused rule groups/plugins first
  - Python: include `S` (flake8-bandit/ruff security)
  - TypeScript/JavaScript: include security plugins/rules in ESLint stack
- `チーム標準` / `team standard`
  - Ask what the team currently uses and match existing conventions
  - If existing config is present, align with it and propose additive diffs only
- Free-form descriptions
  - Interpret intent (strictness, security, readability, performance, migration safety)
  - Map intent to available official categories/presets/rules per language
  - Document the mapping rationale in the evidence trail

---

## Language toolchain defaults (registry summary)

| Language | Linter | Formatter | Type Checker | Notes |
|----------|--------|-----------|-------------|-------|
| Python | ruff | ruff format | mypy | All-in-one; replaces flake8+isort+black |
| TypeScript/JavaScript | ESLint | Prettier | tsc --noEmit | Biome is an emerging alternative |
| Go | golangci-lint | gofmt/goimports | (built-in) | Go toolchain includes formatter |
| Rust | clippy | rustfmt | (built-in) | Cargo includes both |
| Ruby | RuboCop | RuboCop (built-in) | Sorbet/Steep | RuboCop handles both lint and format |
| Java | Checkstyle | google-java-format | (javac) | IDE integration common |
| Kotlin | ktlint/detekt | ktlint | (kotlinc) | ktlint for style, detekt for analysis |

---

## Rule classification criteria

### Essential (always enable)

Rules that prevent bugs, enforce basic style, or catch common mistakes.
These should be enabled for ALL projects regardless of maturity.

Indicators:
- Prevents runtime errors or data loss
- Catches undefined variables, unused imports, syntax issues
- Enforces import ordering (reduces merge conflicts)
- Default-enabled by the linter

### Recommended (enable for quality)

Rules that improve code quality but may require initial cleanup effort.
Enable for new projects; add gradually for existing projects.

Indicators:
- Enforces modern language idioms
- Simplifies code patterns
- Catches potential bugs (not just style)
- May require non-trivial refactoring in existing code

### Framework-specific (conditional)

Rules that only apply when specific frameworks are detected.
Enable when the corresponding framework is present in the project.

Detection: Check manifest files for framework dependencies
(e.g., `django` in requirements.txt → enable Django rules).

---

## Per-language research guide

### Python (ruff)

**Official docs to fetch:**
- Rules reference: `https://docs.astral.sh/ruff/rules/`
- Formatter conflicts: `https://docs.astral.sh/ruff/formatter/#conflicting-lint-rules`

**Essential rules (always enable):**
- `E` (pycodestyle errors) — PEP 8 compliance
- `W` (pycodestyle warnings) — PEP 8 warnings
- `F` (Pyflakes) — logical bugs, unused variables/imports
- `I` (isort) — import ordering
- `B` (flake8-bugbear) — common Python traps
- `UP` (pyupgrade) — modernize syntax
- `RUF` (ruff-specific) — ruff's own bug-prevention rules

**Recommended rules (add for quality):**
- `S` (flake8-bandit) — security checks
- `SIM` (flake8-simplify) — code simplification
- `PLE` (pylint errors) — additional error detection
- `PLW` (pylint warnings) — dangerous patterns
- `FURB` (refurb) — modern code patterns
- `C4` (flake8-comprehensions) — comprehension improvements
- `DTZ` (flake8-datetimez) — timezone-aware datetime
- `T20` (flake8-print) — print statement detection
- `ERA` (eradicate) — commented-out code
- `PERF` (perflint) — performance anti-patterns

**Framework-specific:**
- Django detected → `DJ` (flake8-django)
- FastAPI detected → `FAST` (FastAPI rules)
- pytest detected → `PT` (flake8-pytest-style)
- pandas detected → `PD` (pandas-vet)
- numpy detected → `NPY` (numpy rules)

**Formatter conflict exclusions (when using `ruff format`):**
Exclude: `W191`, `E111`, `E114`, `E117`, `D206`, `D300`, `Q000`, `Q001`, `Q002`, `Q003`, `COM812`, `COM819`, `ISC001`, `ISC002`

**Type checker (mypy):**
- Use `--strict` for new projects
- Use default settings for existing projects (add strictness gradually)

### TypeScript/JavaScript (ESLint)

**Official docs to fetch:**
- Rules reference: `https://eslint.org/docs/latest/rules/`
- Flat config migration: `https://eslint.org/docs/latest/use/configure/configuration-files`

**Essential rules:**
- `eslint:recommended` preset
- `@typescript-eslint/recommended` (for TypeScript projects)
- `no-unused-vars`, `no-undef`, `no-console`

**Recommended rules:**
- `@typescript-eslint/strict` preset
- `import/order` — import ordering

**Framework-specific:**
- React detected → `eslint-plugin-react`, `eslint-plugin-react-hooks`
- Next.js detected → `eslint-config-next`
- Vue detected → `eslint-plugin-vue`

**Formatter conflict (when using Prettier):**
- Use `eslint-config-prettier` to disable conflicting rules

### Go (golangci-lint)

**Official docs to fetch:**
- Linters list: `https://golangci-lint.run/usage/linters/`
- Configuration: `https://golangci-lint.run/usage/configuration/`

**Essential linters:**
- `errcheck` — unchecked errors
- `gosimple` — code simplification
- `govet` — suspicious constructs
- `ineffassign` — ineffective assignments
- `staticcheck` — static analysis
- `unused` — unused code

**Recommended linters:**
- `gofmt` — formatting
- `goimports` — import management
- `misspell` — spelling
- `bodyclose` — HTTP response body close
- `exhaustive` — enum exhaustiveness

### Rust (clippy)

**Official docs to fetch:**
- Lint list: `https://rust-lang.github.io/rust-clippy/master/`

**Essential:**
- Default clippy warnings (enabled by default)

**Recommended:**
- `clippy::pedantic` — stricter lints
- `clippy::nursery` — newer lints (may have false positives)

---

## Graduated application strategy

Apply these strategies after interpreting the user preference profile.
If preference is ambiguous, default to conservative rollout (`最低限` baseline) and document why.

### New project (no existing linter config, no existing code)

1. Enable rule sets according to preference (`strict` => Essential + Recommended + strict presets)
2. Enable Framework-specific rules for detected frameworks
3. Set type checker to strict mode
4. Generate full configuration file

### Existing project (has code, no linter config)

1. Start from preference baseline (`minimal` => Essential only; `strict` => stage strict presets later)
2. Run linter to assess violation count
3. Add this guidance to the evidence trail:

```text
段階的適用ガイダンス:
1. ユーザー希望に対応するベースラインを決定（例: 最低限=Essential のみ、厳しめ=段階適用）
2. まず CI は warning モードで導入（既存違反の可視化）
3. 既存の違反を段階的に修正
4. 修正進捗に応じて Recommended/strict/security ルールを追加
5. フレームワーク固有ルールを追加
```

### Existing project (has linter config)

1. Do NOT overwrite existing config
2. Compare existing config with preference-aligned recommended config
3. Output diff proposal:
   - Missing Essential rules → suggest adding
   - Missing preference-driven rules (Recommended/strict/security) → note as staged optional
   - Conflicting rules → note conflicts

---

## Fail-fast rules

- Official documentation fetch failure → STOP (no fallback to cached/stale data)
- Unknown language → WARN and skip (do not block other languages)
- Multiple conflicting linters → proposal mode only
- Monorepo with 2+ languages → proposal mode only (per-subproject recommendations)

---

## Related

- `.agent/commands/lint-setup.md` — command definition
- `scripts/lint-registry.json` — language-to-linter mapping and rule hints
- `scripts/detect-languages.py` — language detection
- `scripts/lint-setup.py` — recommendation output (agent generates config files)
