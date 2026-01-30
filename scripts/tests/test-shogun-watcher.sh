#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-shogun-watcher] $*" >&2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    eprint "Missing command: $cmd"
    exit 1
  fi
}

require_cmd git
require_cmd python3
require_cmd rg
require_cmd shasum
require_cmd bash

BASH_BIN="$(command -v bash)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-shogun-watcher)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

eprint "workdir=$tmpdir"

mkdir -p "$tmpdir/repo"
cd "$tmpdir/repo"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
echo "ok" > README.md
git add README.md
git commit -q -m "init"

# Initialize ops layout (dashboard.md must exist).
python3 "$REPO_ROOT/scripts/shogun-ops.py" status >/dev/null

common="$(python3 - <<'PY'
import os
import subprocess

def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.STDOUT).decode("utf-8", errors="replace").strip()

abs_git_dir = git("rev-parse", "--absolute-git-dir")
try:
    common_abs = git("rev-parse", "--path-format=absolute", "--git-common-dir")
except subprocess.CalledProcessError:
    common_dir = git("rev-parse", "--git-common-dir")
    if common_dir in (".git", "./.git"):
        common_abs = abs_git_dir
    elif os.path.isabs(common_dir):
        common_abs = os.path.realpath(common_dir)
    else:
        common_abs = os.path.realpath(os.path.join(abs_git_dir, common_dir))
else:
    common_abs = os.path.realpath(common_abs)
print(common_abs)
PY
)"

dashboard_path="$common/agentic-sdd-ops/dashboard.md"
state_path="$common/agentic-sdd-ops/state.yaml"

test -f "$dashboard_path"
test -f "$state_path"

before_updated="$(rg -n '^Updated: ' "$dashboard_path" | head -n1 | sed -e 's/^Updated: //')"

# Prefer fswatch (stubbed) for deterministic watch events.
stub_bin="$tmpdir/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/fswatch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal fswatch stub for tests.
# Wait until a YAML appears under the watched directory, then emit one event line and exit.
dir="${@: -1}"

deadline=$((SECONDS+5))
while (( SECONDS < deadline )); do
  if find "$dir" -type f -name '*.yaml' -print -quit | grep -q .; then
    echo "$dir/event"
    exit 0
  fi
  sleep 0.05
done

echo "timeout" >&2
exit 1
EOF
chmod +x "$stub_bin/fswatch"

# Hold the collect lock to force one failure, then ensure the watcher retries
# without requiring a second filesystem event.
lock_path="$common/agentic-sdd-ops/locks/collect.lock"
mkdir -p "$(dirname -- "$lock_path")"
echo "locked" > "$lock_path"

# Start watcher first, then add a checkin (AC1).
PATH="$stub_bin:$PATH" "$BASH_BIN" "$REPO_ROOT/scripts/shogun-watcher.sh" --once >"$tmpdir/watcher.out" 2>"$tmpdir/watcher.err" &
watcher_pid=$!

# Ensure updated_at has a chance to change (second precision).
sleep 1

worker="ashigaru1"
ts="20260129T121501Z"
checkin_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 40 \
  --worker "$worker" \
  --timestamp "$ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  progress \
)"

test -f "$checkin_path"

# Release lock and let the watcher retry until the queue is drained.
( sleep 0.5; rm -f "$lock_path" ) &
unlock_pid=$!

wait "$watcher_pid"
wait "$unlock_pid" || true

after_updated="$(rg -n '^Updated: ' "$dashboard_path" | head -n1 | sed -e 's/^Updated: //')"

test "$before_updated" != "$after_updated"

cat "$dashboard_path" | rg -q 'progress'

# Collect should have archived the checkin.
test -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts.yaml"
test ! -f "$checkin_path"

# AC2: dry-run outputs watch/collect commands.
dry_out="$(PATH="$stub_bin:$PATH" "$BASH_BIN" "$REPO_ROOT/scripts/shogun-watcher.sh" --dry-run)"
printf '%s\n' "$dry_out" | rg -q '^watch_tool=fswatch$'
printf '%s\n' "$dry_out" | rg -q '^watch_cmd=fswatch '
printf '%s\n' "$dry_out" | rg -q '^collect_cmd=python3 '

# watchexec: --once unsupported must fail-fast (avoid hanging tests/automation).
wx_bin="$tmpdir/watchexecpath"
mkdir -p "$wx_bin"
ln -s "$(command -v git)" "$wx_bin/git"
cat > "$wx_bin/watchexec" <<'EOF'
#!/usr/bin/env bash
# Minimal watchexec stub that does NOT support --once.
if [[ "${1:-}" == "--help" ]]; then
  echo "watchexec 0.0.0"
  echo "USAGE: watchexec -w <path> -- <cmd>"
  exit 0
fi
# Should never be executed in this test.
exit 2
EOF
chmod +x "$wx_bin/watchexec"

set +e
wx_out="$(PATH="$wx_bin" "$BASH_BIN" "$REPO_ROOT/scripts/shogun-watcher.sh" --once --dry-run 2>&1)"
wx_status=$?
set -e

if [[ "$wx_status" -eq 0 ]]; then
  eprint "expected non-zero exit when watchexec lacks --once"
  exit 1
fi
printf '%s\n' "$wx_out" | rg -q 'watchexec does not support --once'

# AC3: no watch tool => non-zero + next action.
mini_bin="$tmpdir/minipath"
mkdir -p "$mini_bin"
ln -s "$(command -v git)" "$mini_bin/git"
ln -s "$(command -v python3)" "$mini_bin/python3"

set +e
no_tool_out="$(PATH="$mini_bin" "$BASH_BIN" "$REPO_ROOT/scripts/shogun-watcher.sh" --dry-run 2>&1)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  eprint "expected non-zero exit when no watch tool is available"
  exit 1
fi

printf '%s\n' "$no_tool_out" | rg -q 'brew install fswatch'
