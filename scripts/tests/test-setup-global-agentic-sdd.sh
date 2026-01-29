#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
setup="$repo_root/scripts/setup-global-agentic-sdd.sh"

if [[ ! -x "$setup" ]]; then
  eprint "Missing script or not executable: $setup"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-setup-global-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

home="$tmpdir/home"
mkdir -p "$home"

HOME="$home" bash "$setup" >/dev/null

if [[ ! -x "$home/.local/bin/agentic-sdd" ]]; then
  eprint "Expected helper CLI to be installed: $home/.local/bin/agentic-sdd"
  exit 1
fi

if [[ ! -f "$home/.codex/skills/agentic-sdd/SKILL.md" ]]; then
  eprint "Expected Codex skill to be installed: $home/.codex/skills/agentic-sdd/SKILL.md"
  exit 1
fi

if [[ ! -f "$home/.codex/skills/agentic-sdd/CHANGELOG.md" ]]; then
  eprint "Expected Codex skill changelog to be installed: $home/.codex/skills/agentic-sdd/CHANGELOG.md"
  exit 1
fi

if ! grep -Fq "# Changelog" "$home/.codex/skills/agentic-sdd/CHANGELOG.md"; then
  eprint "Expected changelog content to include '# Changelog'"
  exit 1
fi

if [[ ! -L "$home/.config/opencode/skills/agentic-sdd" ]]; then
  eprint "Expected OpenCode skill to be symlinked: $home/.config/opencode/skills/agentic-sdd"
  exit 1
fi

# Ensure setup is idempotent: running twice should not create backups for unchanged config files.
HOME="$home" bash "$setup" >/dev/null

if compgen -G "$home/.config/agentic-sdd/default-ref.bak.*" >/dev/null; then
  eprint "Did not expect a backup for default-ref on a second identical run"
  ls -1 "$home/.config/agentic-sdd/default-ref.bak."* >&2
  exit 1
fi

if compgen -G "$home/.config/agentic-sdd/repo.bak.*" >/dev/null; then
  eprint "Did not expect a backup for repo on a second identical run"
  ls -1 "$home/.config/agentic-sdd/repo.bak."* >&2
  exit 1
fi

eprint "OK: scripts/tests/test-setup-global-agentic-sdd.sh"
