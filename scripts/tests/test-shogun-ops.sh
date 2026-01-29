#!/usr/bin/env bash

set -euo pipefail

eprint() { echo "[test-shogun-ops] $*" >&2; }

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

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-shogun-ops)"
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

out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" status)"
printf '%s\n' "$out" | rg -q "^# Agentic-SDD Ops Dashboard$"
printf '%s\n' "$out" | rg -q "^## Summary$"
printf '%s\n' "$out" | rg -q "^## Blocked / Needs Decision$"
printf '%s\n' "$out" | rg -q "^## Recent Check-ins$"

common="$(git rev-parse --path-format=absolute --git-common-dir)"
test -d "$common/agentic-sdd-ops"
test -f "$common/agentic-sdd-ops/state.yaml"
test -f "$common/agentic-sdd-ops/dashboard.md"

# Phase 2: checkin (append-only)
echo "changed" >> README.md
git add README.md

worker="ashigaru1"
ts="20260129T121501Z"
checkin_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 40 \
  --worker "$worker" \
  --timestamp "$ts" \
  --include-staged \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  progress \
)"

test -f "$checkin_path"
cat "$checkin_path" | rg -q '^checkin_id: ashigaru1-18-20260129T121501Z$'
cat "$checkin_path" | rg -q '^issue: 18$'
cat "$checkin_path" | rg -q '^phase: implementing$'
cat "$checkin_path" | rg -q '^progress_percent: 40$'
cat "$checkin_path" | rg -q '^summary: progress$'
cat "$checkin_path" | rg -q '^  files_changed:$'
cat "$checkin_path" | rg -q '^  - README.md$'
cat "$checkin_path" | rg -q '^  command: echo ok$'
cat "$checkin_path" | rg -q '^  result: pass$'

if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 40 "dup" --worker "$worker" --timestamp "$ts" >/dev/null 2>&1; then
  eprint "expected append-only failure but succeeded"
  exit 1
fi

# Phase 2: collect
collect_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out" | rg -q '^processed=1$'

state_path="$common/agentic-sdd-ops/state.yaml"
dashboard_path="$common/agentic-sdd-ops/dashboard.md"

python3 - "$state_path" <<'PY'
import sys
import yaml

state = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
issues = state.get("issues") or {}
assert "18" in issues, issues
entry = issues["18"]
assert entry["phase"] == "implementing"
assert entry["progress_percent"] == 40
assert entry["last_checkin"]["summary"] == "progress"
recent = state.get("recent_checkins") or []
assert recent, recent
assert str(recent[0].get("issue")) == "18"
PY

cat "$dashboard_path" | rg -q '#18'
cat "$dashboard_path" | rg -q 'progress'

test -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts.yaml"
test ! -f "$checkin_path"

# Phase 2: collect lock (must not update state/dashboard)
ts2="20260129T121502Z"
checkin2_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 41 \
  --worker "$worker" \
  --timestamp "$ts2" \
  --include-staged \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  second \
)"
test -f "$checkin2_path"

before_hash="$(shasum -a 256 "$state_path" | awk '{print $1}')"
lock_path="$common/agentic-sdd-ops/locks/collect.lock"
echo "locked" > "$lock_path"

if python3 "$REPO_ROOT/scripts/shogun-ops.py" collect >/dev/null 2>&1; then
  eprint "expected lock failure but succeeded"
  exit 1
fi

after_hash="$(shasum -a 256 "$state_path" | awk '{print $1}')"
test "$before_hash" = "$after_hash"
test -f "$checkin2_path"
rm -f "$lock_path"

# Phase 3: supervise --once (stub gh + worktree check)
mkdir -p scripts
cp -p "$REPO_ROOT/scripts/worktree.sh" scripts/worktree.sh
cp -p "$REPO_ROOT/scripts/extract-issue-files.py" scripts/extract-issue-files.py
chmod +x scripts/worktree.sh

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo=""
if [[ ${1:-} == "-R" ]]; then
  repo="${2:-}"
  shift 2
fi

if [[ ${1:-} != "issue" ]]; then
  echo "unsupported" >&2
  exit 2
fi

sub="${2:-}"
case "$sub" in
  list)
    # Return two parallel-ok issues (1 and 2).
    cat <<'JSON'
[
  {"number":1,"title":"Alpha task","labels":[{"name":"parallel-ok"}]},
  {"number":2,"title":"Beta task","labels":[{"name":"parallel-ok"}]}
]
JSON
    ;;
  view)
    issue="${3:-}"
    body=""
    case "$issue" in
      1)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n- [ ] `src/shared.ts`\n'
        ;;
      2)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/b.ts`\n- [ ] `src/shared.ts`\n'
        ;;
      *)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/other.ts`\n'
        ;;
    esac

    # If --json is present, return the requested fields.
    if [[ "$*" == *"--json"* ]]; then
      if [[ "$*" == *"number,title,labels"* ]]; then
        if [[ "$issue" == "1" ]]; then
          cat <<'JSON'
{"number":1,"title":"Alpha task","labels":[{"name":"parallel-ok"}]}
JSON
        elif [[ "$issue" == "2" ]]; then
          cat <<'JSON'
{"number":2,"title":"Beta task","labels":[{"name":"parallel-ok"}]}
JSON
        else
          cat <<'JSON'
{"number":999,"title":"Other","labels":[{"name":"parallel-ok"}]}
JSON
        fi
      elif [[ "$*" == *"body"* ]]; then
        printf '{"body":%s}\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<<"$body")"
      else
        echo "unsupported json fields" >&2
        exit 2
      fi
    else
      echo "unsupported view format" >&2
      exit 2
    fi
    ;;
  *)
    echo "unsupported subcommand: $sub" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$tmpdir/bin/gh"

git remote add origin https://github.com/OWNER/REPO.git

# Overlap case: issues 1 and 2 overlap on src/shared.ts => decision emitted, no orders.
sup_out="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO)"
printf '%s\n' "$sup_out" | rg -q '^decision='

# Non-overlap case: target only issue 1 => orders emitted.
sup_out2="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1)"
printf '%s\n' "$sup_out2" | rg -q '^orders=1$'
test -f "$common/agentic-sdd-ops/queue/orders/ashigaru1.yaml"

eprint "OK: scripts/tests/test-shogun-ops.sh"
