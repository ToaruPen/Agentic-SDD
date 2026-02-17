---
name: agentic-sdd
description: Download and install Agentic-SDD into the current project directory
argument-hint: "[opencode|codex|claude|all|none] [minimal|full] [--ref <sha|tag|latest>] [--force]"
disable-model-invocation: true
---

# /agentic-sdd - Install Agentic-SDD

Install Agentic-SDD into the current project directory.

Arguments (optional): $ARGUMENTS

- tool: opencode | codex | claude | all | none (default: claude)
- mode: minimal | full (default: minimal)
- ci: none | github-actions (default: none; opt-in)

## Steps

1) Ensure the helper command is available on PATH:

- Recommended: install/update it once by cloning the Agentic-SDD repo and running `./scripts/setup-global-agentic-sdd.sh`.

2) Run the installer via the helper:

```bash
AGENTIC_SDD_DEFAULT_TOOL=claude agentic-sdd $ARGUMENTS
```

3) If the command exits with code 2, conflicts were found. Summarize conflicts and ask whether to re-run with `--force`.

Notes:

- This skill has side effects (creates files in the project). Keep it manual-only.
