#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/watch-codex-review.sh --pr <number> [options]

Poll Codex bot feedback on a PR and trigger a notification hook on new messages.

Note: Event-driven monitoring via `.github/workflows/codex-review-events.yml` is recommended.
This script remains as a local fallback.

Options:
  --pr <number>         Pull request number (required)
  --repo <owner/repo>   Repository (default: detected via gh repo view)
  --interval <seconds>  Poll interval for watch mode (default: 30)
  --state-file <path>   Last-seen event state file
  --notify-cmd <cmd>    Command to run when new event appears
  --once                Run one poll and exit
  --help                Show this help

Environment:
  CODEX_REVIEW_HOOK     Default hook command if --notify-cmd is not provided
  CODEX_BOT_LOGINS      Comma-separated bot logins to watch (required)

Hook environment variables:
  CODEX_EVENT_ID
  CODEX_EVENT_TYPE      issue_comment | inline_comment | review
  CODEX_EVENT_URL
  CODEX_EVENT_CREATED_AT
  CODEX_EVENT_BODY
EOF
}

pr_number=""
repo=""
interval_sec=30
state_file=""
notify_cmd="${CODEX_REVIEW_HOOK:-}"
codex_bot_logins_raw="${CODEX_BOT_LOGINS:-}"
run_once=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      pr_number="${2:-}"
      shift 2
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --interval)
      interval_sec="${2:-}"
      shift 2
      ;;
    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --notify-cmd)
      notify_cmd="${2:-}"
      shift 2
      ;;
    --once)
      run_once=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      eprint "Unknown arg: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$pr_number" || ! "$pr_number" =~ ^[0-9]+$ ]]; then
  eprint "--pr <number> is required"
  exit 2
fi

if [[ ! "$interval_sec" =~ ^[0-9]+$ || "$interval_sec" -lt 1 ]]; then
  eprint "--interval must be an integer >= 1"
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  eprint "gh is required"
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi

if [[ -z "$repo" ]]; then
  eprint "Could not resolve repository. Pass --repo <owner/repo>."
  exit 1
fi

if [[ -z "$codex_bot_logins_raw" ]]; then
  eprint "CODEX_BOT_LOGINS is required"
  exit 2
fi

if [[ -z "$state_file" ]]; then
  state_file="$repo_root/.agentic-sdd/codex-watch/pr-${pr_number}.last_id"
fi

mkdir -p "$(dirname "$state_file")"

if [[ -f "$state_file" ]]; then
  last_seen_key="$(cat "$state_file" 2>/dev/null || true)"
else
  last_seen_key=""
fi

fetch_unseen_events() (
  local last_seen_key_input="$1"
  local tmp_issue tmp_inline tmp_reviews
  tmp_issue="$(mktemp)"
  tmp_inline="$(mktemp)"
  tmp_reviews="$(mktemp)"
  trap 'rm -f "$tmp_issue" "$tmp_inline" "$tmp_reviews"' EXIT

  fetch_endpoint() {
    local endpoint="$1"
    local output_path="$2"
    if ! gh api --paginate --slurp "$endpoint" > "$output_path"; then
      eprint "Failed to poll GitHub API endpoint: $endpoint"
      eprint "Check gh authentication and repository access, then retry."
      return 1
    fi
  }

  fetch_endpoint "repos/$repo/issues/$pr_number/comments" "$tmp_issue"
  fetch_endpoint "repos/$repo/pulls/$pr_number/comments" "$tmp_inline"
  fetch_endpoint "repos/$repo/pulls/$pr_number/reviews" "$tmp_reviews"

  python3 - "$tmp_issue" "$tmp_inline" "$tmp_reviews" "$codex_bot_logins_raw" "$last_seen_key_input" <<'PY'
import json
import sys

issue_path, inline_path, reviews_path, bot_logins_raw, last_seen_key = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
allowed_logins = {x.strip() for x in bot_logins_raw.split(",") if x.strip()}

def load(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
            if isinstance(data, list):
                if data and all(isinstance(page, list) for page in data):
                    merged = []
                    for page in data:
                        for item in page:
                            if isinstance(item, dict):
                                merged.append(item)
                    return merged
                return [item for item in data if isinstance(item, dict)]
    except Exception:
        pass
    return []

def from_issue(item):
    if item.get("user", {}).get("login") not in allowed_logins:
        return None
    return {
        "id": int(item.get("id") or 0),
        "type": "issue_comment",
        "url": item.get("html_url") or "",
        "created_at": item.get("created_at") or "",
        "body": item.get("body") or "",
    }

def from_inline(item):
    if item.get("user", {}).get("login") not in allowed_logins:
        return None
    return {
        "id": int(item.get("id") or 0),
        "type": "inline_comment",
        "url": item.get("html_url") or "",
        "created_at": item.get("created_at") or "",
        "body": item.get("body") or "",
    }

def from_review(item):
    if item.get("user", {}).get("login") not in allowed_logins:
        return None
    return {
        "id": int(item.get("id") or 0),
        "type": "review",
        "url": item.get("html_url") or "",
        "created_at": item.get("submitted_at") or "",
        "body": item.get("body") or "",
    }

events = []
for src, mapper in ((load(issue_path), from_issue), (load(inline_path), from_inline), (load(reviews_path), from_review)):
    for item in src:
        event = mapper(item)
        if event and event["id"] > 0:
            events.append(event)

if not events:
    print("{}")
    raise SystemExit(0)

events.sort(key=lambda e: (str(e.get("created_at") or ""), int(e.get("id") or 0)))

last_created_at = ""
last_id = 0
if last_seen_key:
    if "|" in last_seen_key:
        created_part, id_part = last_seen_key.rsplit("|", 1)
        last_created_at = created_part
        try:
            last_id = int(id_part)
        except ValueError:
            last_created_at = ""
            last_id = 0

unseen = [
    event
    for event in events
    if (str(event.get("created_at") or ""), int(event.get("id") or 0)) > (last_created_at, last_id)
]

print(json.dumps(unseen, ensure_ascii=False))
PY
)

notify_event() {
  local event_json="$1"
  local event_id event_type event_url event_created_at event_body

  event_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id",0))' "$event_json")"
  event_type="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("type",""))' "$event_json")"
  event_url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("url",""))' "$event_json")"
  event_created_at="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("created_at",""))' "$event_json")"
  event_body="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("body",""))' "$event_json")"

  printf '%s\n' "[codex-watch] new event id=${event_id} type=${event_type} at ${event_created_at}"
  if [[ -n "$event_url" ]]; then
    printf '%s\n' "[codex-watch] ${event_url}"
  fi

  if [[ -n "$notify_cmd" ]]; then
    CODEX_EVENT_ID="$event_id" \
    CODEX_EVENT_TYPE="$event_type" \
    CODEX_EVENT_URL="$event_url" \
    CODEX_EVENT_CREATED_AT="$event_created_at" \
    CODEX_EVENT_BODY="$event_body" \
    bash -lc "$notify_cmd"
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    local snippet
    snippet="$(python3 -c 'import sys; s=sys.argv[1].replace("\n", " ")[:120]; s=s.replace("\\", "\\\\").replace("\"", "\\\""); print(s)' "$event_body")"
    osascript - "$snippet" "Codex PR #${pr_number}" "$event_type" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set msgText to item 1 of argv
  set titleText to item 2 of argv
  set subtitleText to item 3 of argv
  display notification msgText with title titleText subtitle subtitleText
end run
APPLESCRIPT
  fi
}

while true; do
  unseen_events_json="$(fetch_unseen_events "$last_seen_key")"
  if [[ "$unseen_events_json" != "[]" ]]; then
    while IFS= read -r event_json; do
      [[ -n "$event_json" ]] || continue
      notify_event "$event_json"

      current_key="$(python3 - "$event_json" <<'PY'
import json
import sys

x = json.loads(sys.argv[1])
print(f"{x.get('created_at', '')}|{x.get('id', 0)}")
PY
)"

      printf '%s\n' "$current_key" > "$state_file"
      last_seen_key="$current_key"
    done < <(python3 - "$unseen_events_json" <<'PY'
import json
import sys

events = json.loads(sys.argv[1])
for event in events:
    print(json.dumps(event, ensure_ascii=False))
PY
)
  fi

  if [[ "$run_once" -eq 1 ]]; then
    break
  fi

  sleep "$interval_sec"
done
