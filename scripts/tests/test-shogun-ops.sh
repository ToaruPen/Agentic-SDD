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
printf '%s\n' "$out" | rg -q "^## Action Required$"
printf '%s\n' "$out" | rg -q "^## Blocked / Needs Decision$"
printf '%s\n' "$out" | rg -q "^## Recent Check-ins$"

# git compatibility: --path-format=absolute may not exist on older git
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
	# compatibility: no candidates section unless explicitly provided
	if rg -q '^candidates:$' "$checkin_path"; then
	  eprint "expected no candidates section but found it"
	  exit 1
	fi

	if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 40 "dup" --worker "$worker" --timestamp "$ts" >/dev/null 2>&1; then
	  eprint "expected append-only failure but succeeded"
	  exit 1
	fi

# phase must be validated (typos should fail-fast)
if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implmenting 40 \
  --worker "$worker" \
  --timestamp "20260129T121504Z" \
  -- \
  badphase \
  >/dev/null 2>&1; then
  eprint "expected invalid phase failure but succeeded"
  exit 1
fi

# percent must be validated (out-of-range should fail-fast)
if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 101 \
  --worker "$worker" \
  --timestamp "20260129T121505Z" \
  -- \
  badpercent \
  >/dev/null 2>&1; then
  eprint "expected invalid percent failure but succeeded"
  exit 1
fi

if python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 1 \
  --worker "../pwn" \
  --timestamp "20260129T121506Z" \
  -- \
  badworker \
  >/dev/null 2>&1; then
  eprint "expected invalid worker id failure but succeeded"
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
action_required = state.get("action_required") or []
assert isinstance(action_required, list), type(action_required)
recent = state.get("recent_checkins") or []
assert recent, recent
assert str(recent[0].get("issue")) == "18"
PY

cat "$dashboard_path" | rg -q '#18'
cat "$dashboard_path" | rg -q 'progress'

test -f "$common/agentic-sdd-ops/archive/checkins/$worker/$ts.yaml"
test ! -f "$checkin_path"

# Phase 2: decisions + action_required (from checkin needs.*)
ts_ar1="20260129T121510Z"
ts_ar2="20260129T121511Z"
ts_ar3="20260129T121512Z"
ts_sc1="20260129T121520Z"
ts_sc2="20260129T121521Z"

checkin_ar1_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 50 \
  --worker "$worker" \
  --timestamp "$ts_ar1" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --needs-approval \
  -- \
  need_approval \
)"
test -f "$checkin_ar1_path"

checkin_ar2_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 55 \
  --worker "$worker" \
  --timestamp "$ts_ar2" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --request-file "app/routes.ts" \
  --request-file "app/profile/model.ts" \
  -- \
  contract_expansion_needed \
)"
test -f "$checkin_ar2_path"

checkin_ar3_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 blocked 55 \
  --worker "$worker" \
  --timestamp "$ts_ar3" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --blocker "waiting_for_approval" \
  -- \
  blocked_waiting \
)"
test -f "$checkin_ar3_path"

# Phase 2: skill candidate (checkin -> collect -> decision)
checkin_sc1_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 56 \
  --worker "$worker" \
  --timestamp "$ts_sc1" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --skill-candidate "contract-expansion-triage" \
  --skill-summary "allowed_files 逸脱時の切り分け手順" \
  -- \
  skill_candidate_1 \
)"
test -f "$checkin_sc1_path"
cat "$checkin_sc1_path" | rg -q '^candidates:$'
cat "$checkin_sc1_path" | rg -q '^  skills:$'
cat "$checkin_sc1_path" | rg -q '^  - name: contract-expansion-triage$'
cat "$checkin_sc1_path" | rg -q '^    summary: allowed_files 逸脱時の切り分け手順$'

# identical candidate should be de-duped (no multiplication)
checkin_sc2_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 57 \
  --worker "$worker" \
  --timestamp "$ts_sc2" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --skill-candidate "contract-expansion-triage" \
  --skill-summary "allowed_files 逸脱時の切り分け手順" \
  -- \
  skill_candidate_2 \
)"
test -f "$checkin_sc2_path"

collect_out_ar="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out_ar" | rg -q '^processed=5$'

decisions_dir="$common/agentic-sdd-ops/queue/decisions"
test -d "$decisions_dir"

python3 - "$state_path" "$dashboard_path" "$decisions_dir" <<'PY'
import glob
import os
import sys
import yaml

state_path, dashboard_path, decisions_dir = sys.argv[1], sys.argv[2], sys.argv[3]
state = yaml.safe_load(open(state_path, "r", encoding="utf-8"))
dash = open(dashboard_path, "r", encoding="utf-8").read()

assert "## Action Required" in dash, dash

paths = sorted(glob.glob(os.path.join(decisions_dir, "*.yaml")))
assert paths, "no decisions created"

types = set()
for p in paths:
    obj = yaml.safe_load(open(p, "r", encoding="utf-8")) or {}
    types.add(obj.get("type"))

assert "approval_required" in types, types
assert "contract_expansion" in types, types
assert "blocker" in types, types
assert "skill_candidate" in types, types

action_required = state.get("action_required") or []
assert isinstance(action_required, list), type(action_required)
kinds = set([it.get("kind") for it in action_required if isinstance(it, dict)])
assert "approval_required" in kinds, kinds
assert "contract_expansion" in kinds, kinds
assert "blocker" in kinds, kinds
assert "skill_candidate" in kinds, kinds
PY

skill_before="$(python3 - "$decisions_dir" <<'PY'
import glob
import os
import sys
import yaml

decisions_dir = sys.argv[1]
paths = sorted(glob.glob(os.path.join(decisions_dir, "*.yaml")))
count = 0
for p in paths:
    obj = yaml.safe_load(open(p, "r", encoding="utf-8")) or {}
    if obj.get("type") == "skill_candidate":
        count += 1
print(count)
PY
)"
test "$skill_before" = "1"

# de-dup: identical approval_required should not multiply
ts_ar4="20260129T121513Z"
checkin_ar4_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 60 \
  --worker "$worker" \
  --timestamp "$ts_ar4" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --needs-approval \
  -- \
  need_approval_again \
)"
test -f "$checkin_ar4_path"

approval_before="$(python3 - "$decisions_dir" <<'PY'
import glob
import os
import sys
import yaml

decisions_dir = sys.argv[1]
paths = sorted(glob.glob(os.path.join(decisions_dir, "*.yaml")))
count = 0
for p in paths:
    obj = yaml.safe_load(open(p, "r", encoding="utf-8")) or {}
    if obj.get("type") == "approval_required":
        count += 1
print(count)
PY
)"

collect_out_ar2="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out_ar2" | rg -q '^processed=1$'

approval_after="$(python3 - "$decisions_dir" <<'PY'
import glob
import os
import sys
import yaml

decisions_dir = sys.argv[1]
paths = sorted(glob.glob(os.path.join(decisions_dir, "*.yaml")))
count = 0
for p in paths:
    obj = yaml.safe_load(open(p, "r", encoding="utf-8")) or {}
    if obj.get("type") == "approval_required":
        count += 1
print(count)
PY
)"

test "$approval_before" = "$approval_after"

# collect must refresh Action Required even when no checkins exist (decisions-only update)
rm -f "$decisions_dir"/*.yaml
python3 "$REPO_ROOT/scripts/shogun-ops.py" collect >/dev/null
python3 - "$state_path" "$dashboard_path" <<'PY'
import sys
import yaml

state_path, dashboard_path = sys.argv[1], sys.argv[2]
state = yaml.safe_load(open(state_path, "r", encoding="utf-8"))
dash = open(dashboard_path, "r", encoding="utf-8").read()

action_required = state.get("action_required") or []
assert action_required == [], action_required
assert "## Action Required" in dash, dash
assert "- (none)" in dash, dash
PY

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

# collect must not trust YAML worker (path traversal guard)
# (A tampered checkin must not write/move files outside ops_root)
evil_dir="$tmpdir/evil-archive"
evil_checkin="$common/agentic-sdd-ops/queue/checkins/$worker/evil.yaml"
cat > "$evil_checkin" <<YAML
version: 1
checkin_id: "evil"
timestamp: "2026-01-29T12:15:04Z"
worker: "$evil_dir"
issue: 18
phase: "implementing"
progress_percent: 1
summary: "evil"
repo:
  worktree_root: "."
  toplevel: "$(pwd)"
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

test -f "$evil_checkin"
collect_out_evil="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out_evil" | rg -q '^processed=1$'
# Vulnerable version would have created evil_dir and moved files there.
test ! -e "$evil_dir"

test -f "$common/agentic-sdd-ops/archive/checkins/$worker/evil.yaml"
test ! -f "$evil_checkin"

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
steps = order.get("required_steps") or []
assert "/create-pr" in steps
assert "/cleanup" in steps
PY

# Fill: if some early candidates are invalid, supervise should pick additional valid candidates.
cat > "$common/agentic-sdd-ops/config.yaml" <<'YAML'
version: 1
policy:
  parallel:
    enabled: true
    max_workers: 2
    require_parallel_ok_label: false
  impl_mode:
    default: impl
    force_tdd_labels: ["tdd", "bug", "high-risk"]
  checkin:
    required_on_phase_change: true
workers:
  - id: "ashigaru1"
  - id: "ashigaru2"
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
  list)
    # Return an invalid issue first (missing change targets), then two valid ones.
    cat <<'JSON'
[
  {"number":10,"title":"Missing targets","labels":[]},
  {"number":1,"title":"Alpha task","labels":[]},
  {"number":3,"title":"Gamma task","labels":[]}
]
JSON
    ;;
  view)
    issue="${3:-}"
    shift 3

    body=""
    case "$issue" in
      10) body=$'## 概要\n\nfrom gh\n\n' ;;
      1) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n' ;;
      3) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/b.ts`\n' ;;
      *) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/other.ts`\n' ;;
    esac

    if [[ "$*" == *"--json"* ]]; then
      if [[ "$*" == *"number,title,labels"* ]]; then
        printf '{"number":%s,"title":"T","labels":[]}' "$issue"
        printf '\n'
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

orders_root="$common/agentic-sdd-ops/queue/orders"
before_orders_fill="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_decisions_fill="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"

sup_out_fill="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO)"
printf '%s\n' "$sup_out_fill" | rg -q '^decision='
printf '%s\n' "$sup_out_fill" | rg -q '^orders=2$'

after_orders_fill="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
test "$((after_orders_fill - before_orders_fill))" = "2"

after_decisions_fill="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_decisions_fill - before_decisions_fill))" = "1"

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
        if [[ "$issue" == "4" ]]; then
          printf '{"number":%s,"title":"T","labels":[{"name":"bug"}]}\n' "$issue"
        else
          printf '{"number":%s,"title":"T","labels":[]}\n' "$issue"
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

orders_dir="$common/agentic-sdd-ops/queue/orders/$worker"
before_orders="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
sup_out3="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1 --targets 3 --targets 4)"
printf '%s\n' "$sup_out3" | rg -q '^orders=3$'
after_orders="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
test "$((after_orders - before_orders))" = "3"

python3 - "$orders_dir" <<'PY'
import glob
import os
import sys
import yaml

orders_dir = sys.argv[1]
paths = glob.glob(os.path.join(orders_dir, "*.yaml"))
found = False
for p in paths:
    order = yaml.safe_load(open(p, "r", encoding="utf-8"))
    if int(order.get("issue") or 0) == 4:
        found = True
        assert order.get("impl_mode") == "tdd", order
        steps = order.get("required_steps") or []
        assert "/tdd" in steps and "/impl" not in steps, steps
        break
assert found, paths
PY

# parallel.enabled=false must limit supervise to a single issued order.
cat > "$common/agentic-sdd-ops/config.yaml" <<'YAML'
version: 1
policy:
  parallel:
    enabled: false
    max_workers: 99
    require_parallel_ok_label: false
  impl_mode:
    default: impl
    force_tdd_labels: ["tdd", "bug", "high-risk"]
  checkin:
    required_on_phase_change: true
workers:
  - id: "ashigaru1"
YAML

before_orders2="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
sup_out_disabled="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1 --targets 3 --targets 4)"
printf '%s\n' "$sup_out_disabled" | rg -q '^orders=1$'
after_orders2="$(ls -1 "$orders_dir" | wc -l | tr -d ' ')"
test "$((after_orders2 - before_orders2))" = "1"

# Restore parallel settings for subsequent tests.
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

# Ensure decision IDs are unique per decision (multiple decisions in one run)
decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
sup_out4="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 10 --targets 11)"
test "$(printf '%s\n' "$sup_out4" | rg -c '^decision=')" = "2"
after_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_decisions - before_decisions))" = "2"

eprint "OK: scripts/tests/test-shogun-ops.sh"
