#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }
warn() { eprint "[AUTOFIX] WARN: $*"; }

issue_number=""
marker=""
comment_url=""

die() {
  local msg="$*"
  eprint "[AUTOFIX] ERROR: $msg"

  if [[ -n "${issue_number:-}" && -n "${marker:-}" ]]; then
    local run_url
    run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
    post_comment "$issue_number" "$(printf '%s\nAutofix failed.\nError: %s\nRun: %s\nComment: %s\n' "$marker" "$msg" "$run_url" "${comment_url:-}")" || true
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

  local bodies
  bodies="$(gh api "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" --paginate --jq ".[] | select(.user.login == \"${marker_author}\") | .body")" || die "Failed to list issue comments via gh api"
  if [[ -z "$bodies" ]]; then
    printf '0'
    return 0
  fi
  printf '%s\n' "$bodies" | grep -cF -- "${marker}" || true
}

main() {
  require_cmd python3
  require_cmd gh
  require_cmd git

  local event_path
  event_path="${GITHUB_EVENT_PATH:-}"
  [[ -n "$event_path" && -f "$event_path" ]] || die "Missing GITHUB_EVENT_PATH"

  local is_pr comment_body comment_login

  issue_number="$(json_get "$event_path" "print(ev.get('issue', {}).get('number', ''))")"
  is_pr="$(json_get "$event_path" "print('pull_request' in ev.get('issue', {}) and ev.get('issue', {}).get('pull_request') is not None)")"
  comment_body="$(json_get "$event_path" "print(ev.get('comment', {}).get('body', '') or '')")"
  comment_login="$(json_get "$event_path" "print(ev.get('comment', {}).get('user', {}).get('login', '') or '')")"
  comment_url="$(json_get "$event_path" "print(ev.get('comment', {}).get('html_url', '') or '')")"

  if [[ "$is_pr" != "True" && "$is_pr" != "true" ]]; then
    eprint "[AUTOFIX] Not a PR comment; skipping"
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

  local run_url
  run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
  on_err() {
    local rc=$?
    post_comment "$issue_number" "$(printf '%s\nAutofix failed (exit=%s).\nRun: %s\nComment: %s\n' "$marker" "$rc" "$run_url" "$comment_url")" || true
    exit "$rc"
  }
  trap on_err ERR

  local allow_csv
  allow_csv="${AGENTIC_SDD_AUTOFIX_BOT_LOGINS:-}"
  if [[ -z "$allow_csv" ]]; then
    eprint "[AUTOFIX] Missing AGENTIC_SDD_AUTOFIX_BOT_LOGINS; skipping (deny-by-default)"
    exit 0
  fi

  if ! csv_contains "$allow_csv" "$comment_login"; then
    eprint "[AUTOFIX] Comment user not allowlisted ($comment_login); skipping"
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

  local head_repo head_ref
  head_repo="$(gh pr view "$issue_number" --repo "$GITHUB_REPOSITORY" --json headRepository --jq '.headRepository.nameWithOwner')"
  head_ref="$(gh pr view "$issue_number" --repo "$GITHUB_REPOSITORY" --json headRefName --jq '.headRefName')"

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
  export AGENTIC_SDD_AUTOFIX_INPUT_PATH="$input_file"
  export AGENTIC_SDD_AUTOFIX_PR_NUMBER="$issue_number"
  export AGENTIC_SDD_AUTOFIX_REPO="$GITHUB_REPOSITORY"
  export AGENTIC_SDD_AUTOFIX_COMMENT_USER="$comment_login"
  export AGENTIC_SDD_AUTOFIX_COMMENT_URL="$comment_url"

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
    post_comment "$issue_number" "$(printf '%s\nAutofix applied and pushed.\n\n%s\n\nRun: %s\nComment: %s\n' "$marker" "$stat" "$run_url" "$comment_url")"
    exit 0
  fi

  git show -1 --patch --no-color >.agentic-sdd-autofix.patch || true
  post_comment "$issue_number" "$(printf '%s\nAutofix produced changes but could not push (branch protection / permissions).\n\n%s\n\nPlease apply manually.\nPatch: attached as a workflow artifact (.agentic-sdd-autofix.patch).\nRun: %s\nComment: %s\n' "$marker" "$stat" "$run_url" "$comment_url")" || true
  exit 0
}

main "$@"
