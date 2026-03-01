# Linter Setup Skill

Guide for researching and configuring linters during `/lint-setup` execution.

This skill defines the agent's research procedure, rule classification criteria,
and official documentation URLs for each supported language.

---

## Research procedure

When `/lint-setup` Phase 4 runs, follow these steps for each detected language:

1. **Identify the recommended toolchain** from `scripts/lint-registry.json`
2. **Fetch the official documentation** using `webfetch` or `librarian`:
   - Use the `docs_url` from the registry entry
   - Fetch the rules/configuration reference page
3. **Classify rules** into Essential / Recommended / Framework-specific (see criteria below)
4. **Check formatter conflicts** using the official conflict documentation
5. **Generate configuration** based on classified rules

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

### New project (no existing linter config, no existing code)

1. Enable Essential + Recommended rules
2. Enable Framework-specific rules for detected frameworks
3. Set type checker to strict mode
4. Generate full configuration file

### Existing project (has code, no linter config)

1. Enable Essential rules only
2. Run linter to assess violation count
3. Add this guidance to the evidence trail:

```text
段階的適用ガイダンス:
1. まず Essential ルールのみで CI を設定（warning モード推奨）
2. 既存の違反を段階的に修正
3. 違反が一定数以下になったら Recommended ルールを追加
4. フレームワーク固有ルールを追加
```

### Existing project (has linter config)

1. Do NOT overwrite existing config
2. Compare existing config with recommended config
3. Output diff proposal:
   - Missing Essential rules → suggest adding
   - Missing Recommended rules → note as optional
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
- `scripts/lint-registry.json` — language-to-linter mapping
- `scripts/detect-languages.py` — language detection
- `scripts/lint-setup.py` — configuration generation
