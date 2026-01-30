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
printf '%s\n' "$out" | rg -q "^## Skill Candidates \\(Approval Pending\\)$"
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
ts_sc3="20260129T121522Z"

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

worker2="ashigaru2"
checkin_sc3_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 18 implementing 58 \
  --worker "$worker2" \
  --timestamp "$ts_sc3" \
  --no-auto-files-changed \
  --tests-command "echo ok" \
  --tests-result pass \
  --skill-candidate "contract-expansion-triage" \
  --skill-summary "allowed_files 逸脱時の切り分け手順" \
  -- \
  skill_candidate_3 \
)"
test -f "$checkin_sc3_path"

collect_out_ar="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_out_ar" | rg -q '^processed=6$'

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
workers = set()
submitters = set()
for p in paths:
    obj = yaml.safe_load(open(p, "r", encoding="utf-8")) or {}
    if obj.get("type") == "skill_candidate":
        count += 1
        req = obj.get("request") or {}
        if isinstance(req, dict):
            ws = req.get("workers") or []
            if isinstance(ws, list):
                for w in ws:
                    if w:
                        workers.add(str(w))
            subs = req.get("submitters") or []
            if isinstance(subs, list):
                for s in subs:
                    if isinstance(s, dict):
                        w = str(s.get("worker") or "")
                        cid = str(s.get("checkin_id") or "")
                        if w:
                            submitters.add(f"{w}|{cid}")
print(count)
assert workers.issuperset({"ashigaru1", "ashigaru2"}), workers
assert any(s.startswith("ashigaru1|") for s in submitters), submitters
assert any(s.startswith("ashigaru2|") for s in submitters), submitters
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
assert "## Skill Candidates (Approval Pending)" in dash, dash
assert "## Skill Candidates (Approval Pending)\n- (none)\n\n" in dash, dash
PY

# decisions-only update: skill_candidate must be listed (name/summary)
cat > "$decisions_dir/DEC-SC-1.yaml" <<'YAML'
version: 1
created_at: "2026-01-29T12:16:00Z"
type: "skill_candidate"
request:
  name: "contract-expansion-triage"
  summary: "allowed_files 逸脱時の切り分け手順"
YAML

python3 "$REPO_ROOT/scripts/shogun-ops.py" collect >/dev/null
cat "$dashboard_path" | rg -q '^## Skill Candidates \(Approval Pending\)$'
cat "$dashboard_path" | rg -q 'contract-expansion-triage'
cat "$dashboard_path" | rg -q 'allowed_files 逸脱時の切り分け手順'

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
# ashigaru1 is busy due to Issue #18 in state (phase=implementing). supervise should assign to an idle worker.
idle_worker="ashigaru2"
test -d "$common/agentic-sdd-ops/queue/orders/$idle_worker"
test "$(ls -1 "$common/agentic-sdd-ops/queue/orders/$idle_worker" | wc -l | tr -d ' ')" = "1"
order_file="$(ls -1 "$common/agentic-sdd-ops/queue/orders/$idle_worker" | head -n 1)"
python3 - "$common/agentic-sdd-ops/queue/orders/$idle_worker/$order_file" <<'PY'
import sys
import yaml

order = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert order["issue"] == 1
assert order["worker"] == "ashigaru2"
steps = order.get("required_steps") or []
assert "/create-pr" in steps
assert "/cleanup" in steps
PY

# Partial-idle case: if there is at least one idle worker, overlap among non-assigned candidates
# must not block assignment (e.g., max_workers=3 but idle_workers=1).
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
  - id: "ashigaru2"
  - id: "ashigaru7"
YAML

python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}

e18 = issues.get("18") or {}
e18["assigned_to"] = "ashigaru1"
e18["phase"] = "implementing"
issues["18"] = e18

issues["19"] = {
    "title": "busy",
    "assigned_to": "ashigaru2",
    "phase": "implementing",
    "progress_percent": 0,
}

state["issues"] = issues
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), sort_keys=False, allow_unicode=True)
PY

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
    # Return three issues; 2 and 3 overlap but 1 does not.
    cat <<'JSON'
[
  {"number":1,"title":"Alpha task","labels":[]},
  {"number":2,"title":"Beta task","labels":[]},
  {"number":3,"title":"Gamma task","labels":[]}
]
JSON
    ;;
  view)
    issue="${3:-}"
    shift 3

    body=""
    case "$issue" in
      1) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n' ;;
      2) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/shared.ts`\n' ;;
      3) body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/shared.ts`\n' ;;
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

orders_root="$common/agentic-sdd-ops/queue/orders"
before_partial="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
sup_out_partial="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO)"
printf '%s\n' "$sup_out_partial" | rg -q '^orders=1$'
after_partial="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
test "$((after_partial - before_partial))" = "1"

idle_worker7="ashigaru7"
test "$(find "$orders_root/$idle_worker7" -type f -name '*.yaml' | wc -l | tr -d ' ')" -ge "1"
order_file7="$(ls -1 "$orders_root/$idle_worker7" | head -n 1)"
python3 - "$orders_root/$idle_worker7/$order_file7" <<'PY'
import sys
import yaml

order = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert order["issue"] == 1
assert order["worker"] == "ashigaru7"
PY

# Restore gh stub for subsequent overlap/no-idle tests (issues 1 and 2 overlap on src/shared.ts).
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

# No-idle case: even when all workers are busy, supervise must still emit decisions
# (e.g., overlap_detected / missing_change_targets) based on deterministic change targets.
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

python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}

e18 = issues.get("18") or {}
e18["assigned_to"] = "ashigaru1"
e18["phase"] = "implementing"
issues["18"] = e18

issues["19"] = {
    "title": "busy",
    "assigned_to": "ashigaru2",
    "phase": "implementing",
    "progress_percent": 0,
}

state["issues"] = issues
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), sort_keys=False, allow_unicode=True)
PY

decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_no_idle="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
sup_out_no_idle="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO)"
printf '%s\n' "$sup_out_no_idle" | rg -q '^decision='
after_no_idle="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_no_idle - before_no_idle))" = "1"

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
  - id: "ashigaru3"
  - id: "ashigaru4"
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

# Multi-target: with 3 idle workers, supervise should issue 3 orders and keep impl_mode=tdd for label-matched issues.
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
  - id: "ashigaru5"
  - id: "ashigaru6"
  - id: "ashigaru7"
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

orders_root="$common/agentic-sdd-ops/queue/orders"
before_orders="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
sup_out3="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1 --targets 3 --targets 4)"
printf '%s\n' "$sup_out3" | rg -q '^orders=3$'
after_orders="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
test "$((after_orders - before_orders))" = "3"

python3 - "$orders_root" <<'PY'
import glob
import os
import sys
import yaml

orders_root = sys.argv[1]
paths = glob.glob(os.path.join(orders_root, "*", "*.yaml"))
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
  - id: "ashigaru8"
  - id: "ashigaru9"
YAML

before_orders2="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
sup_out_disabled="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 1 --targets 3 --targets 4)"
printf '%s\n' "$sup_out_disabled" | rg -q '^orders=1$'
after_orders2="$(find "$orders_root" -type f -name '*.yaml' | wc -l | tr -d ' ')"
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
  - id: "ashigaru8"
  - id: "ashigaru9"
YAML

# Ensure decision IDs are unique per decision (multiple decisions in one run)
decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
sup_out4="$(env PATH="$tmpdir/bin:$PATH" python3 "$REPO_ROOT/scripts/shogun-ops.py" supervise --once --gh-repo OWNER/REPO --targets 10 --targets 11)"
test "$(printf '%s\n' "$sup_out4" | rg -c '^decision=')" = "2"
after_decisions="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_decisions - before_decisions))" = "2"

# Phase 2/collect: contract drift detection against state.issue.contract
state_path="$common/agentic-sdd-ops/state.yaml"

# No drift: files_changed stays within allowed_files => no new decision and issue phase remains as reported.
decisions_dir="$common/agentic-sdd-ops/queue/decisions"
before_no_drift="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
ts_contract_ok="20260129T121520Z"
checkin_contract_ok_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 1 implementing 10 \
  --worker "$worker" \
  --timestamp "$ts_contract_ok" \
  --no-auto-files-changed \
  --files-changed "src/a.ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  contract_ok \
)"
test -f "$checkin_contract_ok_path"
collect_contract_ok_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_contract_ok_out" | rg -q '^processed=1$'
after_no_drift="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$after_no_drift" = "$before_no_drift"

python3 - "$state_path" <<'PY'
import sys
import yaml

state = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
issue = (state.get("issues") or {}).get("1") or {}
assert issue.get("phase") == "implementing", issue
PY

# No drift: allowed_files should support simple glob patterns (e.g. `src/*.ts`).
python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}
issue = issues.get("1") or {}
contract = issue.get("contract") or {}
if not isinstance(contract, dict):
    contract = {}
contract["allowed_files"] = ["src/*.ts"]
issue["contract"] = contract
issues["1"] = issue
state["issues"] = issues
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), sort_keys=False, allow_unicode=True)
PY

before_no_drift_glob="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
ts_contract_ok_glob="20260129T121523Z"
checkin_contract_ok_glob_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 1 implementing 11 \
  --worker "$worker" \
  --timestamp "$ts_contract_ok_glob" \
  --no-auto-files-changed \
  --files-changed "src/a.ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  contract_ok_glob \
)"
test -f "$checkin_contract_ok_glob_path"
collect_contract_ok_glob_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_contract_ok_glob_out" | rg -q '^processed=1$'
after_no_drift_glob="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$after_no_drift_glob" = "$before_no_drift_glob"

# Drift: glob should NOT match across path separators (src/*.ts must not allow src/nested/evil.ts)
before_glob_nested="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
ls -1 "$decisions_dir"/*.yaml > "$tmpdir/decisions.before.contract.globnested" 2>/dev/null || true
ts_contract_glob_nested="20260129T121524Z"
checkin_contract_glob_nested_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 1 implementing 12 \
  --worker "$worker" \
  --timestamp "$ts_contract_glob_nested" \
  --no-auto-files-changed \
  --files-changed "src/nested/evil.ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  contract_glob_nested \
)"
test -f "$checkin_contract_glob_nested_path"
collect_contract_glob_nested_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_contract_glob_nested_out" | rg -q '^processed=1$'
after_glob_nested="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_glob_nested - before_glob_nested))" = "1"

new_glob_nested_decision_path="$(python3 - "$tmpdir/decisions.before.contract.globnested" "$decisions_dir" <<'PY'
import glob
import os
import sys

before_path = sys.argv[1]
decisions_dir = sys.argv[2]
try:
    before = set([ln.strip() for ln in open(before_path, "r", encoding="utf-8").read().splitlines() if ln.strip()])
except FileNotFoundError:
    before = set()
after = set(glob.glob(os.path.join(decisions_dir, "*.yaml")))
added = sorted(after - before)
assert len(added) == 1, added
print(added[0])
PY
)"

python3 - "$new_glob_nested_decision_path" <<'PY'
import sys
import yaml

dec = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert dec.get("type") == "contract_expansion", dec
req = dec.get("request") or {}
assert "src/nested/evil.ts" in (req.get("requested_files") or []), req
PY

# Restore deterministic allowed_files for subsequent drift tests.
python3 - "$state_path" <<'PY'
import sys
import yaml

path = sys.argv[1]
state = yaml.safe_load(open(path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}
issue = issues.get("1") or {}
contract = issue.get("contract") or {}
if not isinstance(contract, dict):
    contract = {}
contract["allowed_files"] = ["src/a.ts"]
issue["contract"] = contract
issues["1"] = issue
state["issues"] = issues
yaml.safe_dump(state, open(path, "w", encoding="utf-8"), sort_keys=False, allow_unicode=True)
PY

# Drift: allowed_files 外の files_changed => blocked + decision(contract_expansion with requested_files + options)
before_drift="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
ls -1 "$decisions_dir"/*.yaml > "$tmpdir/decisions.before.contract" 2>/dev/null || true
ts_contract_drift="20260129T121521Z"
checkin_contract_drift_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 1 implementing 20 \
  --worker "$worker" \
  --timestamp "$ts_contract_drift" \
  --no-auto-files-changed \
  --files-changed "src/evil.ts" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  contract_drift \
)"
test -f "$checkin_contract_drift_path"
collect_contract_drift_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_contract_drift_out" | rg -q '^processed=1$'
after_drift="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_drift - before_drift))" = "1"

new_decision_path="$(python3 - "$tmpdir/decisions.before.contract" "$decisions_dir" <<'PY'
import glob
import os
import sys

before_path = sys.argv[1]
decisions_dir = sys.argv[2]
try:
    before = set([ln.strip() for ln in open(before_path, "r", encoding="utf-8").read().splitlines() if ln.strip()])
except FileNotFoundError:
    before = set()
after = set(glob.glob(os.path.join(decisions_dir, "*.yaml")))
added = sorted(after - before)
assert len(added) == 1, added
print(added[0])
PY
)"

python3 - "$state_path" "$new_decision_path" <<'PY'
import sys
import yaml

state_path, decision_path = sys.argv[1], sys.argv[2]
state = yaml.safe_load(open(state_path, "r", encoding="utf-8"))
issues = state.get("issues") or {}
issue = issues.get("1") or {}
assert issue.get("phase") == "blocked", issue

dec = yaml.safe_load(open(decision_path, "r", encoding="utf-8"))
assert dec.get("type") == "contract_expansion", dec
req = dec.get("request") or {}
assert "src/evil.ts" in (req.get("requested_files") or []), req
opts = req.get("options") or []
assert "拡張" in opts and "差し戻し" in opts and "Issue分割" in opts and "別Issueへ移動" in opts, opts
PY

# Forbidden drift: forbidden_files に一致する変更 => major として decision/blocked に反映
before_forbidden="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
ls -1 "$decisions_dir"/*.yaml > "$tmpdir/decisions.before.forbidden" 2>/dev/null || true
ts_contract_forbidden="20260129T121522Z"
checkin_contract_forbidden_path="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" checkin 1 implementing 30 \
  --worker "$worker" \
  --timestamp "$ts_contract_forbidden" \
  --no-auto-files-changed \
  --files-changed ".agent/rules/issue.md" \
  --tests-command "echo ok" \
  --tests-result pass \
  -- \
  contract_forbidden \
)"
test -f "$checkin_contract_forbidden_path"
collect_contract_forbidden_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" collect)"
printf '%s\n' "$collect_contract_forbidden_out" | rg -q '^processed=1$'
after_forbidden="$(ls -1 "$decisions_dir" | wc -l | tr -d ' ')"
test "$((after_forbidden - before_forbidden))" = "1"

new_forbidden_decision_path="$(python3 - "$tmpdir/decisions.before.forbidden" "$decisions_dir" <<'PY'
import glob
import os
import sys

before_path = sys.argv[1]
decisions_dir = sys.argv[2]
try:
    before = set([ln.strip() for ln in open(before_path, "r", encoding="utf-8").read().splitlines() if ln.strip()])
except FileNotFoundError:
    before = set()
after = set(glob.glob(os.path.join(decisions_dir, "*.yaml")))
added = sorted(after - before)
assert len(added) == 1, added
print(added[0])
PY
)"

python3 - "$new_forbidden_decision_path" <<'PY'
import sys
import yaml

dec = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert dec.get("type") == "contract_expansion", dec
req = dec.get("request") or {}
assert req.get("severity") == "major", req
assert ".agent/rules/issue.md" in (req.get("forbidden_files") or []), req
PY
# Phase 3: skill candidates approve -> generate skills/*.md + update skills/README.md + archive decision
skills_dir="$(pwd)/skills"
mkdir -p "$skills_dir"
cat > "$skills_dir/README.md" <<'MD'
# Skills

## Skill list

### Process Skills

- [worktree-parallel.md](./worktree-parallel.md): worktree patterns
MD
echo "dummy" > "$skills_dir/worktree-parallel.md"

decision_sc1="DEC-SC-1"
cat > "$decisions_dir/$decision_sc1.yaml" <<'YAML'
version: 1
created_at: "2026-01-30T00:00:00Z"
issue: 38
type: "skill_candidate"
request:
  worker: "ashigaru1"
  name: "contract-expansion-triage"
  summary: "allowed_files 逸脱時の切り分け手順"
YAML

approve_out="$(python3 "$REPO_ROOT/scripts/shogun-ops.py" skill --approve "$decision_sc1")"
printf '%s\n' "$approve_out" | rg -q '^skill='
test -f "$skills_dir/contract-expansion-triage.md"
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^# contract-expansion-triage$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Overview$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Principles$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Patterns$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Checklist$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Anti-patterns$'
cat "$skills_dir/contract-expansion-triage.md" | rg -q '^## Related$'
cat "$skills_dir/README.md" | rg -q '\[contract-expansion-triage\.md\]\(\./contract-expansion-triage\.md\): allowed_files 逸脱時の切り分け手順'

test ! -f "$decisions_dir/$decision_sc1.yaml"
test -d "$common/agentic-sdd-ops/archive/decisions"
ls -1 "$common/agentic-sdd-ops/archive/decisions" | rg -q "^$decision_sc1(-[0-9]{3})?\\.yaml$"

# invalid decision-id must fail-fast
if python3 "$REPO_ROOT/scripts/shogun-ops.py" skill --approve "NO-SUCH-DECISION" >/dev/null 2>&1; then
  eprint "expected missing decision-id failure but succeeded"
  exit 1
fi

# type mismatch must fail-fast and not move the decision
decision_wrong="DEC-WRONG-1"
cat > "$decisions_dir/$decision_wrong.yaml" <<'YAML'
version: 1
created_at: "2026-01-30T00:00:01Z"
issue: 38
type: "approval_required"
request:
  worker: "ashigaru1"
  reason: "not a skill candidate"
YAML
if python3 "$REPO_ROOT/scripts/shogun-ops.py" skill --approve "$decision_wrong" >/dev/null 2>&1; then
  eprint "expected type mismatch failure but succeeded"
  exit 1
fi
test -f "$decisions_dir/$decision_wrong.yaml"

# existing skills/<name>.md must fail-fast and not move the decision
decision_exist="DEC-EXIST-1"
echo "# existing" > "$skills_dir/existing-skill.md"
cat > "$decisions_dir/$decision_exist.yaml" <<'YAML'
version: 1
created_at: "2026-01-30T00:00:02Z"
issue: 38
type: "skill_candidate"
request:
  worker: "ashigaru1"
  name: "existing-skill"
  summary: "should fail due to existing file"
YAML
if python3 "$REPO_ROOT/scripts/shogun-ops.py" skill --approve "$decision_exist" >/dev/null 2>&1; then
  eprint "expected existing skill file failure but succeeded"
  exit 1
fi
test -f "$decisions_dir/$decision_exist.yaml"
test ! -f "$common/agentic-sdd-ops/archive/decisions/$decision_exist.yaml"
cat "$skills_dir/README.md" | rg -qv '\[existing-skill\.md\]\(\./existing-skill\.md\)'

eprint "OK: scripts/tests/test-shogun-ops.sh"
