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
require_cmd shasum

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

# Phase 1: status (init ops root + dashboard output)
out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" status)"
printf '%s\n' "$out" | rg -q "^# Agentic-SDD Ops Dashboard$"
printf '%s\n' "$out" | rg -q "^## Summary$"
printf '%s\n' "$out" | rg -q "^## Blocked / Needs Decision$"
printf '%s\n' "$out" | rg -q "^## Recent Check-ins$"

common="$(git rev-parse --path-format=absolute --git-common-dir)"
test -d "$common/agentic-sdd-ops"
test -f "$common/agentic-sdd-ops/config.yaml"
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
python3 - "$checkin_path" "$(pwd)" <<'PY'
import os
import sys
import yaml

path = sys.argv[1]
expected_toplevel = os.path.realpath(sys.argv[2])
obj = yaml.safe_load(open(path, "r", encoding="utf-8"))
repo = obj.get("repo") or {}
assert repo.get("toplevel") == expected_toplevel, repo
assert repo.get("worktree_root") == ".", repo
PY
cat "$checkin_path" | rg -q '^checkin_id: ashigaru1-18-20260129T121501Z$'
cat "$checkin_path" | rg -q '^issue: 18$'
cat "$checkin_path" | rg -q '^phase: implementing$'
cat "$checkin_path" | rg -q '^progress_percent: 40$'
cat "$checkin_path" | rg -q '^summary: progress$'
cat "$checkin_path" | rg -q '^changes:$'
cat "$checkin_path" | rg -q '^  files_changed:$'
cat "$checkin_path" | rg -q '^  - README.md$'
cat "$checkin_path" | rg -q '^tests:$'
cat "$checkin_path" | rg -q '^  command: echo ok$'
cat "$checkin_path" | rg -q '^  result: pass$'

if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 40 "dup" --worker "$worker" --timestamp "$ts" >/dev/null 2>&1; then
  eprint "expected append-only failure but succeeded"
  exit 1
fi

# collect must not lose already-processed checkins if a later checkin is invalid.
bad_path="$common/agentic-sdd-ops/queue/checkins/$worker/bad.yaml"
cat > "$bad_path" <<'YAML'
version: 1
checkin_id: "bad"
timestamp: "2026-01-29T12:15:02Z"
worker: "ashigaru1"
issue: "NaN"
phase: "implementing"
progress_percent: 1
summary: "bad"
repo:
  worktree_root: "."
  toplevel: "/tmp"
changes:
  files_changed: []
tests:
  command: ""
  result: ""
needs:
  approval: false
  contract_expansion:
    requested_files: []
next: []
YAML

if python3 "$REPO_ROOT/scripts/shogun-ops.py" collect >/dev/null 2>&1; then
  eprint "expected invalid checkin failure but succeeded"
  exit 1
fi
test -f "$checkin_path"
test ! -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts.yaml"
rm -f "$bad_path"

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

# Prevent archive overwrites when the same timestamp is re-used after collect.
archive_first="$common/agentic-sdd-ops/archive/checkins/$worker/$ts.yaml"
archive_hash_before="$(shasum -a 256 "$archive_first" | awk '{print $1}')"

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

# Archive collision case: create another checkin with the same timestamp as the first one.
checkin3_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 42 \
  --worker "$worker" \
  --timestamp "$ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  third \
)"
test -f "$checkin3_path"

collect_out2="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out2" | rg -q '^processed=2$'

archive_hash_after="$(shasum -a 256 "$archive_first" | awk '{print $1}')"
test "$archive_hash_before" = "$archive_hash_after"

test -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts2.yaml"
test -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts-001.yaml"

python3 - "$common/agentic-sdd-ops/archive/checkins/$worker/$ts-001.yaml" <<'PY'
import sys
import yaml

obj = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert obj["summary"] == "third"
assert obj["progress_percent"] == 42
PY

# progress_percent=0 must be reflected in state (do not treat 0 as falsy)
ts4="20260129T121503Z"
checkin4_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 0 \
  --worker "$worker" \
  --timestamp "$ts4" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  zero \
)"
test -f "$checkin4_path"

collect_out3="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out3" | rg -q '^processed=1$'

python3 - "$state_path" <<'PY'
import sys
import yaml

state = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
issues = state.get("issues") or {}
entry = issues["18"]
assert entry["progress_percent"] == 0
assert entry["last_checkin"]["summary"] == "zero"
PY

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
    shift 3

    body=""
    case "$issue" in
      1) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n- [ ] `src/shared.ts`\n' ;;
      2) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/b.ts`\n- [ ] `src/shared.ts`\n' ;;
      *) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/other.ts`\n' ;;
    esac

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
test -d "$common/agentic-sdd-ops/queue/orders/$worker"
test "$(ls -1 "$common/agentic-sdd-ops/queue/orders/$worker" | wc -l | tr -d ' ')" = "1"
order_file="$(ls -1 "$common/agentic-sdd-ops/queue/orders/$worker" | head -n 1)"
python3 - "$common/agentic-sdd-ops/queue/orders/$worker/$order_file" <<'PY'
import sys
import yaml

order = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert order["issue"] == 1
assert order["worker"] == "ashigaru1"
PY

# Prevent per-worker order file overwrites (same worker, multiple targets)
cat > "$common/agentic-sdd-ops/config.yaml" <<'YAML'
version: 1
policy:
  parallel:
    enabled: true
    max_workers: 3
    require_parallel_ok_label: false
  impl_mode:
    default: impl
    force_tdd_labels: ["tdd", "bug", "high-risk"]
  checkin:
    required_on_phase_change: true
workers:
  - id: "ashigaru1"
YAML

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
  view)
    issue="${3:-}"
    shift 3

    body=""
    case "$issue" in
      1) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n' ;;
      3) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/b.ts`\n' ;;
      4) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/c.ts`\n' ;;
      10) body=$'## 概要\n\nfrom gh\n\n' ;;
      11) body=$'## 概要\n\nfrom gh\n\n' ;;
      *) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/other.ts`\n' ;;
    esac

    if [[ "$*" == *"--json"* ]]; then
      if [[ "$*" == *"number,title,labels"* ]]; then
        printf '{"number":%s,"title":"T","labels":[]}\n' "$issue"
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

orders_dir="$common/agentic-sdd-ops/queue/orders/$worker"
before_orders="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
sup_out3="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1 --targets 3 --targets 4)"
printf '%s\n' "$sup_out3" | rg -q '^orders=3$'
after_orders="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
test "$((after_orders - before_orders))" = "3"

# Ensure decision IDs are unique per decision (multiple decisions in one run)
decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
sup_out4="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 10 --targets 11)"
test "$(printf '%s\n' "$sup_out4" | rg -c '^decision=')" = "2"
after_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_decisions - before_decisions))" = "2"

eprint "OK: scripts/tests/test-shogun-ops.sh"
