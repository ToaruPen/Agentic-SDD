#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

FORCE=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --quiet) QUIET=true; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/setup-githooks.sh [--force] [--quiet]

Configure git hooks to use .githooks/ (Agentic-SDD gates).

Exit codes:
  0  Success
  2  Refused to overwrite existing core.hooksPath (use --force)
EOF
      exit 0
      ;;
    *)
      eprint "Unknown arg: $1"
      exit 2
      ;;
  esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$root" ]]; then
  eprint "Not in a git repository."
  exit 1
fi

cd "$root"

if [[ ! -d ".githooks" ]]; then
  eprint "Missing .githooks/ directory at repo root."
  exit 1
fi

existing="$(git config --local core.hooksPath 2>/dev/null || true)"
if [[ -n "$existing" && "$existing" != ".githooks" ]]; then
  if [[ "$FORCE" != true ]]; then
    eprint "core.hooksPath is already set: $existing"
    eprint "Refusing to overwrite. Re-run with --force to set it to .githooks"
    exit 2
  fi
fi

git config --local core.hooksPath .githooks

chmod +x .githooks/pre-commit .githooks/pre-push 2>/dev/null || true

if [[ "$QUIET" != true ]]; then
  printf '%s\n' "OK: configured core.hooksPath=.githooks"
fi

