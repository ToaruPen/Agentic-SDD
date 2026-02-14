#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-shogun-github-sync] $*" >&2; }

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
require_cmd grep
require_cmd shasum
require_cmd bash

BASH_BIN="$(command -v bash)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-shogun-github-sync)"
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
git remote add origin "ssh://git@github.com/ToaruPen/Agentic-SDD.git"

# Initialize ops layout.
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

ops_root="$common/agentic-sdd-ops"
state_path="$ops_root/state.yaml"
test -f "$state_path"

# Seed state with a target issue entry.
python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.setdefault("issues", {})
issues["25"] = {
  "title": "Shogun Ops(auto): GitHub sync",
  "phase": "implementing",
  "progress_percent": 40,
  "assigned_to": "ashigaru1",
  "last_checkin": {"at": "2026-01-30T00:00:00Z", "id": "ashigaru1-25-20260130T000000Z", "summary": "progress"},
}
state["updated_at"] = "2026-01-30T00:00:01Z"
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=True, width=120)
PY

stub_bin="$tmpdir/bin"
mkdir -p "$stub_bin"

# Stub gh for deterministic, offline tests.
cat > "$stub_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${GH_STUB_LOG:-}"
if [[ -n "$log" ]]; then
  printf '%s\n' "gh $*" >>"$log"
fi

case "${1:-}" in
  auth)
    if [[ "${2:-}" == "status" ]]; then
      if [[ "${GH_STUB_AUTH_OK:-1}" == "1" ]]; then
        exit 0
      fi
      echo "not logged in" >&2
      exit 1
    fi
    ;;
  issue)
    case "${2:-}" in
      view)
        # Return minimal JSON for label discovery.
        echo '{"labels":[{"name":"ops-phase:backlog"},{"name":"random"}]}'
        exit 0
        ;;
      edit|comment)
        exit 0
        ;;
    esac
    ;;
  label)
    case "${2:-}" in
      create)
        exit 0
        ;;
    esac
    ;;
esac

echo "unexpected gh args: $*" >&2
exit 2
EOF
chmod +x "$stub_bin/gh"

sync_sh="$REPO_ROOT/scripts/shogun-github-sync.sh"

# --- Red: script must exist (TDD starts here) ---
if [[ ! -f "$sync_sh" ]]; then
  eprint "Missing script: $sync_sh"
  exit 1
fi

log_path="$tmpdir/gh.log"
: >"$log_path"

# AC1: successful sync issues comment + label edit.
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  "$BASH_BIN" "$sync_sh" --issue 25 --repo ToaruPen/Agentic-SDD --dry-run >"$tmpdir/dry.out"

cat "$tmpdir/dry.out" | grep -qE '^issue=25$'
cat "$tmpdir/dry.out" | grep -qE '^repo=ToaruPen/Agentic-SDD$'
cat "$tmpdir/dry.out" | grep -qE '^next_action=/impl 25$'

# --repo omitted should be derived from ssh://git@github.com/OWNER/REPO.git origin.
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  "$BASH_BIN" "$sync_sh" --issue 25 --dry-run >"$tmpdir/dry-origin.out"
cat "$tmpdir/dry-origin.out" | grep -qE '^repo=ToaruPen/Agentic-SDD$'

PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  "$BASH_BIN" "$sync_sh" --issue 25 --repo ToaruPen/Agentic-SDD >/dev/null

cat "$log_path" | grep -qE 'gh auth status'
cat "$log_path" | grep -qE 'gh issue view 25'
cat "$log_path" | grep -qE 'gh issue edit 25'
cat "$log_path" | grep -qE 'gh issue comment 25'

# impl_mode=tdd should suggest /tdd.
python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}
issues["25"]["impl_mode"] = "tdd"
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=True, width=120)
PY

PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  "$BASH_BIN" "$sync_sh" --issue 25 --repo ToaruPen/Agentic-SDD --dry-run >"$tmpdir/dry2.out"

cat "$tmpdir/dry2.out" | grep -qE '^next_action=/tdd 25$'

# AC2: auth failure => non-zero and no edits/comments.
: >"$log_path"
set +e
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=0 \
  "$BASH_BIN" "$sync_sh" --issue 25 --repo ToaruPen/Agentic-SDD >/dev/null 2>"$tmpdir/auth.err"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "expected non-zero exit on auth failure, got 0"
  exit 1
fi

cat "$log_path" | grep -qE 'gh auth status'
if cat "$log_path" | grep -qE 'gh issue (edit|comment)'; then
  eprint "expected no issue update calls when auth fails"
  cat "$log_path" >&2
  exit 1
fi

cat "$tmpdir/auth.err" | grep -qE 'auth|login|Not authenticated|not logged in'

eprint "OK: scripts/tests/test-shogun-github-sync.sh"
