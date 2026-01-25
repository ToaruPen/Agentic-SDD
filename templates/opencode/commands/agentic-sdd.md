---
description: Install Agentic-SDD into the current project
agent: build
---

Install Agentic-SDD into the current project directory.

Arguments: $ARGUMENTS

- tool: opencode | codex | claude | all | none (default: opencode)
- mode: minimal | full (default: minimal)
- ci: none | github-actions (default: none; opt-in)

Use the shared helper script `agentic-sdd` (recommended location: `~/.local/bin/agentic-sdd`).

Steps:

1) If `agentic-sdd` is not available on PATH, explain how to install it:
   - Clone the Agentic-SDD repo once.
   - Run: `./scripts/setup-global-agentic-sdd.sh`

2) Run the installer via the helper:

```bash
AGENTIC_SDD_DEFAULT_TOOL=opencode agentic-sdd $ARGUMENTS
```

3) If the command exits with code 2, summarize conflicts and ask whether to re-run with `--force`.

4) If `opencode` is selected, remind the user to restart OpenCode so it reloads `.opencode/`.
