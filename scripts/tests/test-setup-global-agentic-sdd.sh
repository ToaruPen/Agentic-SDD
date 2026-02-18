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

if [[ "$(tr -d '\n' < "$home/.config/agentic-sdd/default-ref")" != "main" ]]; then
  eprint "Expected default ref to be 'main'"
  exit 1
fi

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

custom_src="$tmpdir/custom-src"
custom_remote="$tmpdir/custom-remote.git"
mkdir -p "$custom_src"
git init -q -b trunk "$custom_src"
git -C "$custom_src" config user.name test
git -C "$custom_src" config user.email test@example.com
printf 'x\n' > "$custom_src/README.md"
git -C "$custom_src" add README.md
git -C "$custom_src" commit -q -m "init"
git clone -q --bare "$custom_src" "$custom_remote"

home_custom="$tmpdir/home-custom"
mkdir -p "$home_custom"
HOME="$home_custom" AGENTIC_SDD_REPO="$custom_remote" bash "$setup" >/dev/null

if [[ "$(tr -d '\n' < "$home_custom/.config/agentic-sdd/default-ref")" != "trunk" ]]; then
  eprint "Expected default ref to follow AGENTIC_SDD_REPO HEAD ('trunk')"
  exit 1
fi

home_fail="$tmpdir/home-fail"
mkdir -p "$home_fail"
if HOME="$home_fail" AGENTIC_SDD_REPO="$tmpdir/nonexistent-remote.git" bash "$setup" >"$home_fail/stdout" 2>"$home_fail/stderr"; then
  eprint "Expected setup to fail when remote default branch cannot be detected"
  exit 1
fi

if ! grep -Fq "Set AGENTIC_SDD_DEFAULT_REF explicitly" "$home_fail/stderr"; then
  eprint "Expected guidance to set AGENTIC_SDD_DEFAULT_REF on detection failure"
  exit 1
fi

home_override="$tmpdir/home-override"
mkdir -p "$home_override"
HOME="$home_override" AGENTIC_SDD_REPO="$tmpdir/nonexistent-remote.git" AGENTIC_SDD_DEFAULT_REF="main" bash "$setup" >/dev/null

if [[ "$(tr -d '\n' < "$home_override/.config/agentic-sdd/default-ref")" != "main" ]]; then
  eprint "Expected explicit AGENTIC_SDD_DEFAULT_REF to bypass remote detection"
  exit 1
fi

eprint "OK: scripts/tests/test-setup-global-agentic-sdd.sh"
