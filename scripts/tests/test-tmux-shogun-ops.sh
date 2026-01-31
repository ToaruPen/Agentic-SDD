#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-tmux-shogun-ops] $*" >&2; }

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

shim="$REPO_ROOT/scripts/tmux"
if [[ ! -x "$shim" ]]; then
  eprint "Missing shim or not executable: $shim"
  exit 1
fi

# --- shogun-ops dry-run path should not require tmux ---
out="$("$shim" --shogun-ops --dry-run)"
printf '%s\n' "$out" | rg -F -q "tmux new-session -d -s shogun-ops -n ops"
printf '%s\n' "$out" | rg -F -q "tmux attach -t shogun-ops"

out_custom="$("$shim" --shogun-ops --dry-run --session myops --window mywin)"
printf '%s\n' "$out_custom" | rg -F -q "tmux new-session -d -s myops -n mywin"
printf '%s\n' "$out_custom" | rg -F -q "tmux attach -t myops"

# --- forwarding path: should exec the real tmux binary found in PATH ---
tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-tmux-shim-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "REAL_TMUX_ARGS=$*" >&2
exit 0
EOF
chmod +x "$tmpdir/bin/tmux"

set +e
err="$({ PATH="$tmpdir/bin:$PATH" "$shim" list-sessions 1>/dev/null; } 2>&1)"
code=$?
set -e

if [[ "$code" -ne 0 ]]; then
  eprint "Expected forwarding call to exit 0, got: $code"
  printf '%s\n' "$err" >&2
  exit 1
fi

printf '%s\n' "$err" | rg -F -q "REAL_TMUX_ARGS=list-sessions"

eprint "OK: scripts/tests/test-tmux-shogun-ops.sh"

