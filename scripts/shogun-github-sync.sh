#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/shogun-github-sync.sh --issue <n> [--repo <owner/repo>] [--dry-run]

Sync local Agentic-SDD Shogun Ops state to a GitHub Issue:
- Add a status comment (phase/progress/blocked/next action)
- Update labels (phase + blocked)

Notes:
- This command is intended to be run by "Middle" only (single writer).
- Ops data lives under: <git-common-dir>/agentic-sdd-ops/

Options:
  --issue <n>        Target Issue number (required)
  --repo <o/r>       GitHub repo (default: derived from git origin)
  --dry-run          Print actions without calling gh write operations
  -h, --help         Show this help
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ISSUE=""
GH_REPO=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      ISSUE="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      eprint "Unknown arg: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  eprint "Missing required flag: --issue <n>"
  exit 2
fi
if ! [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
  eprint "Invalid --issue (expected integer): $ISSUE"
  exit 2
fi

detect_repo_from_origin() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    return 1
  fi

  if [[ "$url" == https://github.com/* || "$url" == http://github.com/* ]]; then
    local path="${url#*github.com/}"
    path="${path%.git}"
    echo "$path"
    return 0
  fi
  if [[ "$url" == git@github.com:* ]]; then
    local path="${url#git@github.com:}"
    path="${path%.git}"
    echo "$path"
    return 0
  fi
  if [[ "$url" == ssh://git@github.com/* ]]; then
    local path="${url#ssh://git@github.com/}"
    path="${path%.git}"
    echo "$path"
    return 0
  fi
  return 1
}

if [[ -z "$GH_REPO" ]]; then
  if ! GH_REPO="$(detect_repo_from_origin)"; then
    eprint "Failed to detect --repo from git origin. Set explicitly: --repo OWNER/REPO"
    exit 2
  fi
fi

if ! command -v gh >/dev/null 2>&1; then
  eprint "gh not found."
  eprint "Next action: install GitHub CLI (gh)."
  exit 127
fi

# Resolve git common dir -> ops state path.
if ! abs_git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)"; then
  eprint "Not a git repository (git rev-parse failed)."
  exit 1
fi

common_abs=""
if common_abs="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  :
else
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "$common_dir" ]]; then
    eprint "Failed to resolve git common dir."
    exit 1
  fi
  if [[ "$common_dir" == ".git" || "$common_dir" == "./.git" ]]; then
    common_abs="$abs_git_dir"
  elif [[ "$common_dir" = /* ]]; then
    common_abs="$common_dir"
  else
    common_abs="$abs_git_dir/$common_dir"
  fi
  common_abs="$(cd -- "$common_abs" && pwd -P)"
fi

ops_root="$common_abs/agentic-sdd-ops"
state_path="$ops_root/state.yaml"

if [[ ! -f "$state_path" ]]; then
  eprint "state.yaml not found: $state_path"
  eprint "Next action: initialize ops layout:"
  eprint "  python3 scripts/shogun-ops.py status"
  exit 2
fi

read_issue_state() {
  python3 - "$state_path" "$ISSUE" <<'PY'
import sys
import yaml

state_path = sys.argv[1]
issue = str(int(sys.argv[2]))

state = yaml.safe_load(open(state_path, "r", encoding="utf-8")) or {}
issues = state.get("issues") or {}
entry = issues.get(issue) if isinstance(issues, dict) else None

def out(k, v):
    v = "" if v is None else str(v)
    v = v.replace("\n", " ").strip()
    print(f"{k}={v}")

out("issue_found", "1" if isinstance(entry, dict) else "0")
out("updated_at", state.get("updated_at") or "")

phase = ""
progress = ""
assigned_to = ""
last_at = ""
last_summary = ""
impl_mode = ""
if isinstance(entry, dict):
    phase = entry.get("phase") or ""
    progress = entry.get("progress_percent")
    assigned_to = entry.get("assigned_to") or ""
    impl_mode = entry.get("impl_mode") or ""
    last = entry.get("last_checkin") or {}
    if isinstance(last, dict):
        last_at = last.get("at") or ""
        last_summary = last.get("summary") or ""

out("phase", phase)
out("progress_percent", progress if progress is not None else "")
out("assigned_to", assigned_to)
out("impl_mode", impl_mode)
out("last_checkin_at", last_at)
out("last_checkin_summary", last_summary)

blocked = state.get("blocked") or []
reasons = []
if isinstance(blocked, list):
    for item in blocked:
        if not isinstance(item, dict):
            continue
        raw = item.get("issue")
        if raw is None:
            continue
        if str(raw) != issue:
            continue
        reason = item.get("reason") or ""
        if reason:
            reasons.append(str(reason))

out("blocked_reasons", ",".join(reasons))
PY
}

kv="$(read_issue_state)"

get_kv() {
  local key="$1"
  printf '%s\n' "$kv" | awk -F= -v "k=$key" '$1==k{print substr($0, length(k)+2)}'
}

issue_found="$(get_kv issue_found)"
phase="$(get_kv phase)"
progress_percent="$(get_kv progress_percent)"
assigned_to="$(get_kv assigned_to)"
updated_at="$(get_kv updated_at)"
impl_mode_raw="$(get_kv impl_mode)"
last_checkin_at="$(get_kv last_checkin_at)"
last_checkin_summary="$(get_kv last_checkin_summary)"
blocked_reasons="$(get_kv blocked_reasons)"

if [[ "$issue_found" != "1" ]]; then
  eprint "Issue #$ISSUE is not present in local state.yaml."
  eprint "Next actions:"
  eprint "  1) Run supervise to register the issue in state:"
  eprint "     python3 scripts/shogun-ops.py supervise --once --targets $ISSUE --gh-repo $GH_REPO"
  eprint "  2) Or create a checkin then collect:"
  eprint "     python3 scripts/shogun-ops.py checkin $ISSUE implementing 0 -- -- \"seed\""
  eprint "     python3 scripts/shogun-ops.py collect"
  exit 2
fi

is_blocked="0"
if [[ -n "$blocked_reasons" || "$phase" == "blocked" ]]; then
  is_blocked="1"
fi

impl_mode="impl"
impl_mode_note=""
if [[ "$impl_mode_raw" == "tdd" ]]; then
  impl_mode="tdd"
elif [[ "$impl_mode_raw" == "impl" ]]; then
  impl_mode="impl"
elif [[ -z "$impl_mode_raw" ]]; then
  # Default to /impl for existing state.yaml entries that predate `impl_mode`.
  # This matches the default policy in `scripts/shogun-ops.py` (impl_mode.default=impl).
  impl_mode="impl"
  impl_mode_note="(default)"
fi

next_action="(none)"
case "$phase" in
  backlog|"")
    next_action="python3 scripts/shogun-ops.py supervise --once --targets $ISSUE --gh-repo $GH_REPO"
    ;;
  estimating)
    next_action="/estimation $ISSUE"
    ;;
  implementing)
    if [[ "$impl_mode" == "tdd" ]]; then
      next_action="/tdd $ISSUE"
    else
      next_action="/impl $ISSUE"
    fi
    ;;
  reviewing)
    next_action="/review-cycle"
    ;;
  blocked)
    next_action="check local decisions queue and resolve blockers"
    ;;
  done)
    next_action="/cleanup"
    ;;
esac

comment_body="$(cat <<EOF
<!-- agentic-sdd:shogun-ops-sync v1 -->
### Agentic-SDD Ops Status (local)

- Issue: #$ISSUE
- Phase: ${phase:-backlog}
- Impl mode: ${impl_mode} ${impl_mode_note}
- Progress: ${progress_percent:-0}%
- Assigned: ${assigned_to:-}
- Updated: ${updated_at:-}
- Blocked: $( [[ "$is_blocked" == "1" ]] && echo "yes" || echo "no" )
- Blocked reasons: ${blocked_reasons:-}
- Last checkin: ${last_checkin_at:-} ${last_checkin_summary:-}
- Next: $next_action
EOF
)"

phase_label="ops-phase:${phase:-backlog}"
blocked_label="ops-blocked"

phase_color="6c757d"
case "$phase" in
  estimating) phase_color="0d6efd" ;;
  implementing) phase_color="20c997" ;;
  reviewing) phase_color="6610f2" ;;
  blocked) phase_color="dc3545" ;;
  done) phase_color="198754" ;;
  backlog|"") phase_color="6c757d" ;;
esac

blocked_color="dc3545"

ensure_label() {
  local name="$1"
  local color="$2"
  local desc="$3"
  gh label create "$name" --repo "$GH_REPO" --color "$color" --description "$desc" --force >/dev/null
}

list_issue_labels() {
  gh issue view "$ISSUE" --repo "$GH_REPO" --json labels
}

compute_label_deltas() {
  python3 -c '
import json
import sys

phase_label = sys.argv[1]
blocked_label = sys.argv[2]
is_blocked = sys.argv[3] == "1"

obj = json.load(sys.stdin)
labels = obj.get("labels") or []
names = []
if isinstance(labels, list):
    for l in labels:
        if isinstance(l, dict) and l.get("name"):
            names.append(str(l["name"]))

remove = []
for n in names:
    if n.startswith("ops-phase:"):
        remove.append(n)
    if n == blocked_label:
        remove.append(n)

add = [phase_label]
if is_blocked:
    add.append(blocked_label)

def join(xs):
    return ",".join([x for x in xs if x])

print("add=" + join(add))
print("remove=" + join(remove))
' "$phase_label" "$blocked_label" "$is_blocked"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'issue=%s\n' "$ISSUE"
  printf 'repo=%s\n' "$GH_REPO"
  printf 'state=%s\n' "$state_path"
  printf 'impl_mode=%s\n' "$impl_mode"
  printf 'next_action=%s\n' "$next_action"
  printf 'phase_label=%s\n' "$phase_label"
  printf 'blocked_label=%s\n' "$blocked_label"
  printf 'comment_preview=%s\n' "$(printf '%s' "$comment_body" | shasum -a 256 | awk '{print $1}')"
  exit 0
fi

# AC2: auth/permission preflight (fail fast before any write operations).
if ! gh auth status >/dev/null 2>&1; then
  eprint "Not authenticated to GitHub via gh."
  eprint "Next action: run:"
  eprint "  gh auth login"
  exit 1
fi

# Ensure labels exist first (avoid partial updates due to missing labels).
ensure_label "$phase_label" "$phase_color" "Agentic-SDD ops phase ($phase)"
ensure_label "$blocked_label" "$blocked_color" "Agentic-SDD ops blocked"

labels_json="$(list_issue_labels)"
deltas="$(printf '%s' "$labels_json" | compute_label_deltas)"
add_labels="$(printf '%s\n' "$deltas" | awk -F= '$1=="add"{print $2}')"
remove_labels="$(printf '%s\n' "$deltas" | awk -F= '$1=="remove"{print $2}')"

edit_args=(issue edit "$ISSUE" --repo "$GH_REPO")
if [[ -n "$add_labels" ]]; then
  edit_args+=(--add-label "$add_labels")
fi
if [[ -n "$remove_labels" ]]; then
  edit_args+=(--remove-label "$remove_labels")
fi

gh "${edit_args[@]}" >/dev/null
gh issue comment "$ISSUE" --repo "$GH_REPO" --body "$comment_body" >/dev/null
