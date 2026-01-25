---
name: agentic-sdd
description: Download and install Agentic-SDD into the current project directory
disable-model-invocation: true
---

# /agentic-sdd - Install Agentic-SDD

Install Agentic-SDD into the current project directory.

Arguments (optional): $ARGUMENTS

- tool: opencode | codex | claude | all | none (default: all)
- mode: minimal | full (default: minimal)
- ci: none | github-actions (default: none; opt-in)

## Steps

1) Ensure the helper command is available on PATH:

- Recommended: install/update it once by cloning the Agentic-SDD repo and running `./scripts/setup-global-agentic-sdd.sh`.

2) Run the installer via the helper:

```bash
AGENTIC_SDD_DEFAULT_TOOL=all agentic-sdd --ref latest $ARGUMENTS
```

3) If the command exits with code 2, conflicts were found. Summarize conflicts and ask whether to re-run with `--force`.
