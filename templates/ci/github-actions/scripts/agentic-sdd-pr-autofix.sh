#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }
warn() { eprint "[AUTOFIX] WARN: $*"; }

issue_number=""
marker=""
comment_url=""
event_type=""
target_sha=""
source_event_key=""

build_failure_body() {
  local msg="$1"
  local run_url
  run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"

  printf '%s\nAutofix failed.\nError: %s\nTarget SHA: %s\nRun: %s\nComment: %s\nSource event: %s\n' \
    "$marker" "$msg" "${target_sha:-unknown}" "$run_url" "${comment_url:-}" "${source_event_key:-unknown}"
}

die() {
  local msg="$*"
  eprint "[AUTOFIX] ERROR: $msg"

  if [[ -n "${issue_number:-}" && -n "${marker:-}" ]]; then
    post_comment "$issue_number" "$(build_failure_body "$msg")" || true
  fi

  exit 1
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || die "Missing required command: $name"
}

validate_single_line() {
  local name="$1"
  local value="$2"
  local max_len="$3"

  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    die "$name must be a single line"
  fi
  if (( ${#value} > max_len )); then
    die "$name is too long (${#value} > ${max_len})"
  fi
}

json_get() {
  local json_path="$1"
  local py="$2"
  python3 - "$json_path" <<PY
import json
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    ev = json.load(f)
${py}
PY
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

validate_path_only_cmd() {
  local cmd="$1"

  if [[ ! "$cmd" =~ ^\./[A-Za-z0-9_./-]+$ ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD must be a repo-relative path like ./scripts/autofix.sh (no args). Got: $cmd"
  fi

  if [[ "$cmd" == *"/../"* || "$cmd" == "./.." || "$cmd" == "./../"* || "$cmd" == *"/.." ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD must not contain '..' path segments. Got: $cmd"
  fi

  if [[ "$cmd" == *"/.git/"* || "$cmd" == "./.git" || "$cmd" == "./.git/"* ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD must not point into .git/. Got: $cmd"
  fi

  local repo_root repo_root_real cmd_real
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo_root" ]] || die "Failed to resolve repo root (git rev-parse --show-toplevel)"

  repo_root_real="$(python3 - "$repo_root" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
  )"
  cmd_real="$(python3 - "$cmd" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
  )"

  case "$cmd_real" in
    "$repo_root_real"/*) ;;
    *) die "AGENTIC_SDD_AUTOFIX_CMD must resolve under repo root. Got: $cmd -> $cmd_real" ;;
  esac

  if [[ ! -f "$cmd" ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD not found: $cmd"
  fi

  if [[ ! -x "$cmd" ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD is not executable: $cmd (chmod +x)"
  fi
}

post_comment() {
  local issue_number="$1"
  local body="$2"
  gh api "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" -f body="$body" >/dev/null
}

has_label() {
  local issue_number="$1"
  local label_name="$2"

  local labels
  labels="$(gh api "repos/$GITHUB_REPOSITORY/issues/$issue_number" --jq '.labels[].name')" || die "Failed to fetch issue labels via gh api"
  if printf '%s\n' "$labels" | grep -Fxq "$label_name"; then
    return 0
  fi
  return 1
}

count_marker_comments() {
  local issue_number="$1"
  local marker="$2"
  local marker_author
  marker_author="github-actions[bot]"

  local counted_comments comment_filter
  comment_filter=".[] | select(.user.login == \"${marker_author}\") | select((.body | contains(\"${marker}\")) and ((.body | contains(\"Autofix applied and pushed.\")) or (.body | contains(\"Autofix produced changes but could not push\")) or (.body | contains(\"Autofix stopped: reached max iterations\")))) | .id"
  counted_comments="$(gh api "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" --paginate --jq "$comment_filter")" || die "Failed to list issue comments via gh api"
  if [[ -z "$counted_comments" ]]; then
    printf '0'
    return 0
  fi
  printf '%s\n' "$counted_comments" | wc -l | tr -d ' '
}

has_source_event_already_processed() {
  local issue_number="$1"
  local marker="$2"
  local source_key="$3"

  if [[ -z "$source_key" ]]; then
    return 1
  fi

  local marker_author
  marker_author="github-actions[bot]"

  local processed_match
  processed_match="$(gh api "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" --paginate --jq ".[] | select(.user.login == \"${marker_author}\") | select((.body | contains(\"${marker}\")) and (.body | contains(\"Source event: ${source_key}\")) and (.body | contains(\"Autofix applied and pushed.\"))) | .id")" || die "Failed to list issue comments via gh api"
  if [[ -n "$processed_match" ]]; then
    return 0
  fi
  return 1
}

extract_event() {
  local json_path="$1"

  python3 - "$json_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    ev = json.load(f)

event_name = (ev.get('action') and '')

github_event = ''
if 'pull_request' in ev and 'comment' in ev and 'issue' not in ev:
    github_event = 'pull_request_review_comment'
elif 'pull_request' in ev and 'review' in ev:
    github_event = 'pull_request_review'
elif 'issue' in ev and 'comment' in ev:
    github_event = 'issue_comment'

event_type = ''
issue_number = ''
is_pr = False
comment_body = ''
comment_login = ''
comment_url = ''
source_event_key = ''

if github_event == 'issue_comment':
    issue = ev.get('issue', {})
    is_pr = issue.get('pull_request') is not None
    issue_number = str(issue.get('number') or '')
    comment = ev.get('comment', {})
    comment_body = comment.get('body') or ''
    comment_login = (comment.get('user') or {}).get('login') or ''
    comment_url = comment.get('html_url') or ''
    event_type = 'issue_comment'
    source_event_key = f"issue_comment:{comment.get('id') or ''}:{comment_url}"
elif github_event == 'pull_request_review':
    pr = ev.get('pull_request', {})
    review = ev.get('review', {})
    is_pr = True
    issue_number = str(pr.get('number') or '')
    comment_body = review.get('body') or ''
    comment_login = (review.get('user') or {}).get('login') or ''
    comment_url = review.get('html_url') or ''
    event_type = 'review'
    source_event_key = f"review:{review.get('id') or ''}:{comment_url}"
elif github_event == 'pull_request_review_comment':
    pr = ev.get('pull_request', {})
    comment = ev.get('comment', {})
    is_pr = True
    issue_number = str(pr.get('number') or '')
    comment_body = comment.get('body') or ''
    comment_login = (comment.get('user') or {}).get('login') or ''
    comment_url = comment.get('html_url') or ''
    event_type = 'inline'
    source_event_key = f"inline:{comment.get('id') or ''}:{comment_url}"

print(json.dumps({
    'event_type': event_type,
    'issue_number': issue_number,
    'is_pr': bool(is_pr),
    'comment_body': comment_body,
    'comment_login': comment_login,
    'comment_url': comment_url,
    'source_event_key': source_event_key,
}, ensure_ascii=False))
PY
}

main() {
  require_cmd python3
  require_cmd gh
  require_cmd git

  local event_path
  event_path="${GITHUB_EVENT_PATH:-}"
  [[ -n "$event_path" && -f "$event_path" ]] || die "Missing GITHUB_EVENT_PATH"

  local is_pr comment_body comment_login event_json
  event_json="$(extract_event "$event_path")"

  issue_number="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("issue_number", ""))' "$event_json")"
  is_pr="$(python3 -c 'import json,sys; print(str(json.loads(sys.argv[1]).get("is_pr", False)))' "$event_json")"
  comment_body="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("comment_body", ""))' "$event_json")"
  comment_login="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("comment_login", ""))' "$event_json")"
  comment_url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("comment_url", ""))' "$event_json")"
  event_type="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("event_type", ""))' "$event_json")"
  source_event_key="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("source_event_key", ""))' "$event_json")"

  if [[ "$is_pr" != "True" && "$is_pr" != "true" ]]; then
    eprint "[AUTOFIX] Not a PR event; skipping"
    exit 0
  fi

  if [[ -z "$issue_number" ]]; then
    die "Failed to detect PR number from event payload"
  fi

  marker="${AGENTIC_SDD_AUTOFIX_MARKER:-<!-- agentic-sdd:autofix v1 -->}"
  if [[ "$comment_body" == *"$marker"* ]]; then
    eprint "[AUTOFIX] Marker comment; skipping"
    exit 0
  fi

  local run_url review_mention
  run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
  review_mention="${AGENTIC_SDD_PR_REVIEW_MENTION:-}"
  if [[ -z "$review_mention" ]]; then
    die "Missing AGENTIC_SDD_PR_REVIEW_MENTION"
  fi
  validate_single_line "AGENTIC_SDD_PR_REVIEW_MENTION" "$review_mention" 200
  on_err() {
    local rc=$?
    post_comment "$issue_number" "$(build_failure_body "Autofix failed (exit=$rc).")" || true
    exit "$rc"
  }
  trap on_err ERR

  local allow_csv
  allow_csv="${AGENTIC_SDD_AUTOFIX_BOT_LOGINS:-}"
  if [[ -z "$allow_csv" ]]; then
    die "Missing AGENTIC_SDD_AUTOFIX_BOT_LOGINS"
  fi

  if ! csv_contains "$allow_csv" "$comment_login"; then
    eprint "[AUTOFIX] Comment user not allowlisted ($comment_login); skipping"
    exit 0
  fi

  if [[ "$event_type" == "review" ]]; then
    local trimmed_review_body
    trimmed_review_body="$(trim "$comment_body")"
    if [[ -z "$trimmed_review_body" ]]; then
      eprint "[AUTOFIX] Empty pull_request_review body; skipping"
      exit 0
    fi
  fi

  if has_source_event_already_processed "$issue_number" "$marker" "$source_event_key"; then
    eprint "[AUTOFIX] Duplicate event already processed ($source_event_key); skipping"
    exit 0
  fi

  local optin_label
  optin_label="${AGENTIC_SDD_AUTOFIX_OPTIN_LABEL:-autofix-enabled}"
  if ! has_label "$issue_number" "$optin_label"; then
    eprint "[AUTOFIX] Opt-in label not present ($optin_label); skipping"
    exit 0
  fi

  local max_iters
  max_iters="${AGENTIC_SDD_AUTOFIX_MAX_ITERS:-3}"
  if ! [[ "$max_iters" =~ ^[0-9]+$ ]]; then
    die "AGENTIC_SDD_AUTOFIX_MAX_ITERS must be an integer. Got: $max_iters"
  fi

  local prior
  prior="$(count_marker_comments "$issue_number" "$marker")"
  if [[ -n "$prior" && "$prior" =~ ^[0-9]+$ ]] && (( prior >= max_iters )); then
    warn "Max iterations reached ($prior >= $max_iters); posting stop note"
    post_comment "$issue_number" "$(printf '%s\nAutofix stopped: reached max iterations (%s/%s).\nRun: https://github.com/%s/actions/runs/%s\n' "$marker" "$prior" "$max_iters" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID")"
    exit 0
  fi

  local head_repo head_ref base_ref
  head_repo="$(gh pr view "$issue_number" --repo "$GITHUB_REPOSITORY" --json headRepository --jq '.headRepository.nameWithOwner')"
  head_ref="$(gh pr view "$issue_number" --repo "$GITHUB_REPOSITORY" --json headRefName --jq '.headRefName')"
  base_ref="$(gh pr view "$issue_number" --repo "$GITHUB_REPOSITORY" --json baseRefName --jq '.baseRefName')"
  if [[ -z "$base_ref" ]]; then
    base_ref="main"
  fi

  if [[ -z "$head_repo" || -z "$head_ref" ]]; then
    die "Failed to fetch PR head info via gh"
  fi

  if [[ "$head_repo" != "$GITHUB_REPOSITORY" ]]; then
    post_comment "$issue_number" "$(printf '%s\nAutofix skipped: fork PRs are not supported for auto-push in MVP.\nComment: %s\n' "$marker" "$comment_url")"
    exit 0
  fi

  local autofix_cmd
  autofix_cmd="${AGENTIC_SDD_AUTOFIX_CMD:-}"
  if [[ -z "$autofix_cmd" ]]; then
    die "Missing AGENTIC_SDD_AUTOFIX_CMD (required when opt-in is enabled)"
  fi
  validate_path_only_cmd "$autofix_cmd"

  # Fail-closed: record the base version of the autofix script, then require the
  # checked-out PR branch to contain the exact same script contents.
  # This avoids executing a PR-modified script while still preserving $0/BASH_SOURCE
  # semantics for scripts that locate resources relative to their own path.
  local base_autofix_hash
  base_autofix_hash="$(git hash-object -- "$autofix_cmd" 2>/dev/null || true)"
  if [[ -z "$base_autofix_hash" ]]; then
    die "Failed to hash AGENTIC_SDD_AUTOFIX_CMD on base checkout: $autofix_cmd"
  fi

  local input_file
  input_file=""
  cleanup_input_file_on_exit() {
    [[ -n "$input_file" ]] && rm -f "$input_file"
  }
  trap cleanup_input_file_on_exit EXIT

  eprint "[AUTOFIX] Fetching branch: $head_ref"
  git check-ref-format --branch "$head_ref" >/dev/null 2>&1 || die "Invalid PR head ref: $head_ref"
  git fetch --no-tags -- origin "$head_ref"
  git checkout -B "$head_ref" "FETCH_HEAD"

  local pr_autofix_hash
  pr_autofix_hash="$(git hash-object -- "$autofix_cmd" 2>/dev/null || true)"
  if [[ -z "$pr_autofix_hash" ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD not found on PR checkout: $autofix_cmd"
  fi
  if [[ "$pr_autofix_hash" != "$base_autofix_hash" ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD differs from base checkout; refusing to run: $autofix_cmd"
  fi
  if [[ ! -x "$autofix_cmd" ]]; then
    die "AGENTIC_SDD_AUTOFIX_CMD is not executable on PR checkout: $autofix_cmd"
  fi

  input_file="$(mktemp)"
  printf '%s' "$comment_body" >"$input_file"
  target_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  export AGENTIC_SDD_AUTOFIX_INPUT_PATH="$input_file"
  export AGENTIC_SDD_AUTOFIX_PR_NUMBER="$issue_number"
  export AGENTIC_SDD_AUTOFIX_REPO="$GITHUB_REPOSITORY"
  export AGENTIC_SDD_AUTOFIX_COMMENT_USER="$comment_login"
  export AGENTIC_SDD_AUTOFIX_COMMENT_URL="$comment_url"
  export AGENTIC_SDD_AUTOFIX_EVENT_TYPE="$event_type"

  eprint "[AUTOFIX] Running autofix command: $autofix_cmd"
  "$autofix_cmd"

  local test_cmd
  test_cmd="${AGENTIC_SDD_AUTOFIX_TEST_CMD:-}"
  if [[ -n "$test_cmd" ]]; then
    validate_single_line "AGENTIC_SDD_AUTOFIX_TEST_CMD" "$test_cmd" 500
    eprint "[AUTOFIX] Running test command: $test_cmd"
    bash -lc "$test_cmd"
  fi

  if [[ -z "$(git status --porcelain=v1)" ]]; then
    post_comment "$issue_number" "$(printf '%s\nAutofix: no changes needed.\nRun: %s\nComment: %s\n' "$marker" "$run_url" "$comment_url")"
    exit 0
  fi

  git add -A
  if git diff --cached --quiet; then
    post_comment "$issue_number" "$(printf '%s\nAutofix: no staged changes.\nRun: %s\nComment: %s\n' "$marker" "$run_url" "$comment_url")"
    exit 0
  fi

  local msg
  msg="chore(autofix): apply review fixes"
  git -c user.name="agentic-sdd" -c user.email="agentic-sdd@users.noreply.github.com" commit -m "$msg" >/dev/null

  local stat
  stat="$(git show --stat --oneline -1 | sed -e 's/[[:space:]]\+$//')"

  if git push origin "HEAD:$head_ref" >/dev/null 2>&1; then
    local pushed_sha
    pushed_sha="$(git rev-parse HEAD)"
    post_comment "$issue_number" "$(printf '%s\nAutofix applied and pushed.\n\n%s\n\nRun: %s\nComment: %s\nSource event: %s\n\n%s\n\nこのPRを再レビューしてください（ベースブランチ %s との差分として）。対象は現時点の head SHA (%s) です。\n\n現時点のPRに残っている「実行可能な指摘」だけを挙げ、既に解消済みの事項の繰り返しは避けてください。\n' "$marker" "$stat" "$run_url" "$comment_url" "${source_event_key:-unknown}" "$review_mention" "$base_ref" "$pushed_sha")"
    exit 0
  fi

  git show -1 --patch --no-color >.agentic-sdd-autofix.patch || true
  local failed_sha
  failed_sha="$(git rev-parse HEAD 2>/dev/null || printf '%s' "${target_sha:-unknown}")"
  post_comment "$issue_number" "$(printf '%s\nAutofix produced changes but could not push (branch protection / permissions).\n\n%s\n\nPlease apply manually.\nPatch: attached as a workflow artifact (.agentic-sdd-autofix.patch).\nTarget SHA: %s\nRun: %s\nComment: %s\nSource event: %s\n' "$marker" "$stat" "$failed_sha" "$run_url" "$comment_url" "${source_event_key:-unknown}")" || true
  exit 0
}

main "$@"
