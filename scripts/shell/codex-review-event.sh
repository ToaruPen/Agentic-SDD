#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

die() {
  eprint "[codex-review-event] error: $*"
  exit 1
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || die "missing required command: $name"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

csv_contains() {
  local csv="$1"
  local needle="$2"
  local item
  IFS=',' read -r -a items <<<"$csv"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    if [[ -n "$item" && "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

check_auth() {
  local require_auth="$1"
  if [[ "$require_auth" != "1" ]]; then
    return 0
  fi

  require_cmd gh

  if ! gh auth status >/dev/null 2>&1; then
    die "GitHub authentication failed. Ensure GH_TOKEN/GITHUB_TOKEN has required permissions."
  fi

  if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    die "GITHUB_REPOSITORY is required for permission checks"
  fi

  if ! gh api "repos/${GITHUB_REPOSITORY}" --jq '.full_name' >/dev/null 2>&1; then
    die "GitHub API access failed for ${GITHUB_REPOSITORY}. Check repository permissions."
  fi
}

main() {
  require_cmd python3

  local event_name event_path bot_logins snippet_max require_auth
  event_name="${GITHUB_EVENT_NAME:-}"
  event_path="${GITHUB_EVENT_PATH:-}"
  bot_logins="${CODEX_BOT_LOGINS:-}"
  snippet_max="${CODEX_REVIEW_SNIPPET_MAX:-160}"
  require_auth="${CODEX_REVIEW_REQUIRE_GH_AUTH:-1}"

  [[ -n "$event_name" ]] || die "GITHUB_EVENT_NAME is required"
  [[ -n "$event_path" && -f "$event_path" ]] || die "GITHUB_EVENT_PATH is required and must point to an existing file"
  [[ -n "$bot_logins" ]] || die "CODEX_BOT_LOGINS is required"
  [[ "$snippet_max" =~ ^[0-9]+$ ]] || die "CODEX_REVIEW_SNIPPET_MAX must be an integer"

  check_auth "$require_auth"

  local parsed_json
  parsed_json="$(python3 - "$event_path" "$event_name" "$snippet_max" <<'PY'
import json
import sys

event_path, event_name, snippet_max_raw = sys.argv[1], sys.argv[2], sys.argv[3]
snippet_max = int(snippet_max_raw)

with open(event_path, "r", encoding="utf-8") as f:
    ev = json.load(f)

def clean(s):
    if not s:
        return ""
    return " ".join(str(s).split())

def snippet(s):
    text = clean(s)
    if len(text) <= snippet_max:
        return text
    if snippet_max <= 3:
        return text[:snippet_max]
    return text[: snippet_max - 3] + "..."

kind = ""
actor = ""
pr_number = ""
pr_url = ""
body = ""
should_process = "false"
reason = ""

if event_name == "issue_comment":
    issue = ev.get("issue", {})
    if not issue.get("pull_request"):
        reason = "no-op: issue_comment is not on a pull request"
    else:
        kind = "issue"
        actor = (ev.get("comment") or {}).get("user", {}).get("login", "")
        pr_number = str(issue.get("number", ""))
        pr_url = issue.get("html_url", "")
        body = (ev.get("comment") or {}).get("body", "")
        should_process = "true"
elif event_name == "pull_request_review":
    review = ev.get("review", {})
    pr = ev.get("pull_request", {})
    kind = "review"
    actor = review.get("user", {}).get("login", "")
    pr_number = str(pr.get("number", ""))
    pr_url = pr.get("html_url", "")
    body = review.get("body", "")
    should_process = "true"
elif event_name == "pull_request_review_comment":
    comment = ev.get("comment", {})
    pr = ev.get("pull_request", {})
    kind = "inline"
    actor = comment.get("user", {}).get("login", "")
    pr_number = str(pr.get("number", ""))
    pr_url = pr.get("html_url", "")
    body = comment.get("body", "")
    should_process = "true"
else:
    reason = f"no-op: unsupported event '{event_name}'"

print(json.dumps({
    "should_process": should_process,
    "reason": reason,
    "kind": kind,
    "actor": actor,
    "pr_number": pr_number,
    "pr_url": pr_url,
    "body_snippet": snippet(body),
}, ensure_ascii=False))
PY
)"

  local should_process reason kind actor pr_number pr_url body_snippet
  eval "$(python3 - "$parsed_json" <<'PY'
import json
import shlex
import sys

data = json.loads(sys.argv[1])

for key in ("should_process", "reason", "kind", "actor", "pr_number", "pr_url", "body_snippet"):
    value = "" if data.get(key) is None else str(data.get(key))
    print(f"{key}={shlex.quote(value)}")
PY
)"

  if [[ "$should_process" != "true" ]]; then
    eprint "[codex-review-event] ${reason}"
    exit 0
  fi

  if [[ -z "$actor" || -z "$pr_number" || -z "$pr_url" || -z "$kind" ]]; then
    die "event payload is missing required fields (actor/pr_number/pr_url/kind)"
  fi

  if ! csv_contains "$bot_logins" "$actor"; then
    eprint "[codex-review-event] no-op: actor not in CODEX_BOT_LOGINS (actor=${actor})"
    exit 0
  fi

  printf '%s\n' "[codex-review-event] type=${kind} pr_number=${pr_number} pr_url=${pr_url}"
  printf '%s\n' "[codex-review-event] snippet=${body_snippet}"
}

main "$@"
