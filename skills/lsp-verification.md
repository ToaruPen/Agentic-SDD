# LSP Verification

## Overview

Patterns and checklists for using Language Server Protocol (LSP) tools during implementation
to ensure type safety, impact analysis, and safe refactoring.

This skill is designed to be loaded via the `skill` tool when delegating implementation tasks
to sub-agents. It complements the LSP verification gate in `.agent/rules/impl-gate.md`.

---

## Principles

1. **Verify after every edit** — Run `lsp_diagnostics` on each changed file immediately after editing, not just at the end.
2. **Measure impact before changing** — Use `lsp_find_references` before modifying signatures, types, or interfaces.
3. **Use LSP rename over grep** — `lsp_prepare_rename` → `lsp_rename` is semantically aware; grep + replace is not.
4. **Navigate, don't guess** — Use `lsp_goto_definition` to understand unfamiliar code instead of assuming from context.

---

## Patterns

### When to use each LSP tool

| Situation                          | LSP Tool                                          | Purpose                                                    |
| ---------------------------------- | ------------------------------------------------- | ---------------------------------------------------------- |
| After editing a file               | `lsp_diagnostics`                                 | Confirm error count is 0                                   |
| Before changing a function signature | `lsp_find_references`                            | Find all call sites that need updating                     |
| Adding a DI parameter              | `lsp_find_references`                            | Check if tests and other consumers need updates            |
| YAGNI decision (remove code?)      | `lsp_find_references`                            | Count actual usage sites — decide with evidence, not guess |
| Type or interface change           | `lsp_find_references`                            | Trace propagation to implementors, consumers, and tests    |
| Renaming a symbol                  | `lsp_prepare_rename` → `lsp_rename`              | Semantically safe rename across the workspace              |
| Understanding unfamiliar code      | `lsp_goto_definition`                            | Jump to the definition instead of searching manually       |
| Checking workspace-wide symbols    | `lsp_symbols` (scope: workspace)                 | Find symbols by name across the project                    |
| Checking file outline              | `lsp_symbols` (scope: document)                  | Understand file structure before editing                   |

### Workflow: Edit → Verify → Continue

```text
1. Edit file(s)
2. Run lsp_diagnostics on each edited file
3. If errors > 0:
   a. Fix the errors
   b. Re-run lsp_diagnostics
   c. Repeat until error count is 0
4. Continue to next edit
```

### Workflow: Refactor → Impact Check → Apply

```text
1. Identify the symbol to change
2. Run lsp_find_references to list all usage sites
3. Plan changes for all affected files
4. Apply changes
5. Run lsp_diagnostics on all affected files
6. Confirm error count is 0
```

### Workflow: Rename

```text
1. Run lsp_prepare_rename to verify the rename is valid
2. Run lsp_rename with the new name
3. Run lsp_diagnostics on affected files to confirm no errors
```

---

## Checklist

### Required (gate condition)

- [ ] `lsp_diagnostics` run on all edited files with error count = 0
- [ ] `lsp_find_references` run before any refactor/rename to confirm impact scope

### Recommended

- [ ] `lsp_find_references` used for type/interface changes to trace propagation
- [ ] `lsp_prepare_rename` → `lsp_rename` used instead of grep + replace for symbol renames
- [ ] `lsp_goto_definition` used to understand unfamiliar symbols before modifying them
- [ ] `lsp_symbols` (document) used to understand file structure before large edits

---

## Anti-patterns

| Anti-pattern                           | Why it's bad                                              | Better alternative                                    |
| -------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| Skip `lsp_diagnostics` after edit      | Type errors silently accumulate                           | Run after every file edit                             |
| Grep + replace for rename              | Misses semantic boundaries (strings, comments, imports)   | `lsp_prepare_rename` → `lsp_rename`                  |
| Guess usage count for YAGNI            | May remove code that is actually used                     | `lsp_find_references` for evidence-based decisions    |
| Run `lsp_diagnostics` only at the end  | Late discovery = expensive fix                            | Run after each edit for fast feedback                 |
| Delegate without LSP requirements      | Sub-agent skips verification (no enforcement)             | Include LSP tools in REQUIRED TOOLS + MUST DO         |

---

## Related

- `.agent/rules/impl-gate.md` — LSP verification gate (mandatory gate conditions)
- `.agent/rules/dod.md` — Definition of Done (includes LSP check)
- `skills/testing.md` — testing strategy (complements LSP verification)
- `skills/debugging.md` — debugging strategies (LSP tools aid diagnosis)
