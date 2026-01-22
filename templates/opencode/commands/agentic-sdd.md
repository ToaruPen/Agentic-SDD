---
description: Install Agentic-SDD into the current project
agent: build
---

Install Agentic-SDD into the current project directory.

Interpret command arguments ($ARGUMENTS):
- tool: opencode | codex | claude | all
- mode: minimal | full

Steps:
1) Determine project root:
   - Try: `git rev-parse --show-toplevel`
   - If it fails, use the current working directory.
2) Determine install mode:
   - If $ARGUMENTS contains `full`, use `full`; otherwise use `minimal`.
3) Determine tool selection:
   - If $ARGUMENTS contains one of the tool names, use it.
   - Otherwise, ask the user to choose (recommend `opencode`).
4) Clone Agentic-SDD into a temporary directory:
   - Repo: https://github.com/ToaruPen/Agentic-SDD.git
   - Use a fresh temp dir (e.g., via `mktemp -d`).
5) Run the installer from the cloned repo:

```bash
bash "<temp>/Agentic-SDD/scripts/install-agentic-sdd.sh" \
  --target "<project_root>" \
  --mode "<minimal|full>" \
  --tool "<none|opencode|codex|claude|all>"
```

If the installer exits with code 2, summarize the conflicts and ask whether to re-run with `--force`.

If `opencode` is selected, remind the user to restart OpenCode so it reloads `.opencode/`.
