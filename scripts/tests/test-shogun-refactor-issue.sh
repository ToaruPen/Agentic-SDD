#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-shogun-refactor-issue] $*" >&2; }

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
require_cmd bash

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-shogun-refactor-issue)"
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

worker="ashigaru1"
ts="20260129T121507Z"
draft_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-draft \
  --title "Refactor: split mixed responsibilities" \
  --worker "$worker" \
  --timestamp "$ts" \
  --smell "mixed responsibilities" \
  --smell "duplication" \
  --risk "med" \
  --impact "local" \
  --file "README.md" \
  -- \
  要約 \
)"

test -f "$draft_path"
test "$draft_path" = "$ops_root/queue/refactor-drafts/$worker/$ts.yaml"

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

args=("$@")
if [[ "${args[0]:-}" == "-R" || "${args[0]:-}" == "--repo" ]]; then
  args=("${args[@]:2}")
fi

case "${args[0]:-}" in
  auth)
    if [[ "${args[1]:-}" == "status" ]]; then
      if [[ "${GH_STUB_AUTH_OK:-1}" == "1" ]]; then
        exit 0
      fi
      echo "not logged in" >&2
      exit 1
    fi
    ;;
  label)
    if [[ "${args[1]:-}" == "create" ]]; then
      exit 0
    fi
    ;;
  issue)
    if [[ "${args[1]:-}" == "create" ]]; then
      echo "https://github.com/ToaruPen/Agentic-SDD/issues/99"
      exit 0
    fi
    ;;
esac

echo "unexpected gh args: $*" >&2
exit 2
EOF
chmod +x "$stub_bin/gh"

log_path="$tmpdir/gh.log"
: >"$log_path"

# AC1: successful issue creation archives the draft.
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-issue \
    --gh-repo ToaruPen/Agentic-SDD \
    --draft "$draft_path" >"$tmpdir/out.txt"

cat "$tmpdir/out.txt" | rg -q '^repo=ToaruPen/Agentic-SDD$'
cat "$tmpdir/out.txt" | rg -q '^issue=99$'
cat "$tmpdir/out.txt" | rg -q '^url=https://github.com/ToaruPen/Agentic-SDD/issues/99$'
archived="$(cat "$tmpdir/out.txt" | rg '^archived_draft=' | sed 's/^archived_draft=//')"
test -f "$archived"
test ! -f "$draft_path"
test "$archived" = "$ops_root/archive/refactor-drafts/$worker/$ts.yaml"

cat "$log_path" | rg -q 'gh auth status'
cat "$log_path" | rg -q 'label create refactor-candidate'
cat "$log_path" | rg -q 'issue create'

# AC2: --gh-repo omitted should be derived from origin.
ts2="20260129T121508Z"
draft2="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-draft \
  --title "Refactor: rename confusing API" \
  --worker "$worker" \
  --timestamp "$ts2" \
  --smell "naming" \
  -- \
  要約2 \
)"
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=1 \
  python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-issue \
    --draft "$draft2" >"$tmpdir/out2.txt"
cat "$tmpdir/out2.txt" | rg -q '^repo=ToaruPen/Agentic-SDD$'

# AC3: auth failure => non-zero and no label/issue calls; draft remains.
ts3="20260129T121509Z"
draft3="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-draft \
  --title "Refactor: extract helper" \
  --worker "$worker" \
  --timestamp "$ts3" \
  -- \
  要約3 \
)"
: >"$log_path"
set +e
PATH="$stub_bin:$PATH" GH_STUB_LOG="$log_path" GH_STUB_AUTH_OK=0 \
  python3 "$REPO_ROOT/scripts/shogun-ops.py" refactor-issue \
    --gh-repo ToaruPen/Agentic-SDD \
    --draft "$draft3" >/dev/null 2>"$tmpdir/auth.err"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "expected non-zero exit on auth failure, got 0"
  exit 1
fi

test -f "$draft3"
cat "$log_path" | rg -q 'gh auth status'
if cat "$log_path" | rg -q 'gh label create|gh issue create'; then
  eprint "expected no label/issue calls when auth fails"
  cat "$log_path" >&2
  exit 1
fi

cat "$tmpdir/auth.err" | rg -q 'auth|login|Not authenticated|not logged in'

eprint "OK: scripts/tests/test-shogun-refactor-issue.sh"
