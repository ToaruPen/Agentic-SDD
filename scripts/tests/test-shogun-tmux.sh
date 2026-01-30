#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-shogun-tmux] $*" >&2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    eprint "Missing command: $cmd"
    exit 1
  fi
}

require_cmd bash
require_cmd rg

sh="$REPO_ROOT/scripts/shogun-tmux.sh"
if [[ ! -f "$sh" ]]; then
  eprint "Missing script: $sh"
  exit 1
fi

# --- dry-run: init ---
# The new implementation uses pane_id capture (-P -F "#{pane_id}").
# Verify the key commands are present.
out_init="$(bash "$sh" --dry-run init)"
printf '%s\n' "$out_init" | rg -F -q "tmux new-session -d -s shogun-ops -n ops"
printf '%s\n' "$out_init" | rg -F -q -- "-T upper"
printf '%s\n' "$out_init" | rg -F -q -- "-T middle"
printf '%s\n' "$out_init" | rg -F -q -- "-T ashigaru1"
printf '%s\n' "$out_init" | rg -F -q -- "-T ashigaru2"
printf '%s\n' "$out_init" | rg -F -q -- "-T ashigaru3"
# Verify pane_id capture is present (not hardcoded indexes)
printf '%s\n' "$out_init" | rg -F -q '#{pane_id}'

# --- dry-run: send-order ---
# The new implementation uses list-panes to find pane by title.
out_send="$(bash "$sh" --dry-run send-order)"
printf '%s\n' "$out_send" | rg -F -q "tmux list-panes"
printf '%s\n' "$out_send" | rg -F -q "tmux send-keys"
printf '%s\n' "$out_send" | rg -F -q "python3 scripts/shogun-ops.py supervise --once"
printf '%s\n' "$out_send" | rg -F -q "Enter"

# --- missing tmux should fail-fast (non-dry-run) ---
# Build PATH without tmux dir (if tmux exists).
orig_path="$PATH"
new_path=""
if command -v tmux >/dev/null 2>&1; then
  tmux_dir="$(dirname "$(command -v tmux)")"
  IFS=':' read -r -a parts <<<"$orig_path"
  for p in "${parts[@]}"; do
    if [[ -z "$p" ]]; then
      continue
    fi
    if [[ "$p" == "$tmux_dir" ]]; then
      continue
    fi
    if [[ -z "$new_path" ]]; then
      new_path="$p"
    else
      new_path="$new_path:$p"
    fi
  done
else
  new_path="$orig_path"
fi

set +e
err="$({ PATH="$new_path" bash "$sh" init 1>/dev/null; } 2>&1)"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected non-zero exit when tmux is missing, but got 0"
  exit 1
fi

printf '%s\n' "$err" | rg -q "tmux not found"
printf '%s\n' "$err" | rg -q "brew install tmux|apt-get install tmux"

eprint "OK: scripts/tests/test-shogun-tmux.sh"
