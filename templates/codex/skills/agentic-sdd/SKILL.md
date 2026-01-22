---
name: agentic-sdd
description: Download and install Agentic-SDD into the current project directory
---

# /agentic-sdd - Install Agentic-SDD

Install Agentic-SDD into the current project.

Arguments (optional): $ARGUMENTS

- tool: opencode | codex | claude | all | none (default: codex)
- mode: minimal | full (default: minimal)

## Steps

1) Ensure the helper command is available:

- Recommended: install it once by cloning the Agentic-SDD repo and running `./scripts/setup-global-agentic-sdd.sh`.

2) Run the installer via the helper:

```bash
AGENTIC_SDD_DEFAULT_TOOL=codex agentic-sdd $ARGUMENTS
```

3) If the command exits with code 2, conflicts were found. Summarize conflicts and ask whether to re-run with `--force`.
