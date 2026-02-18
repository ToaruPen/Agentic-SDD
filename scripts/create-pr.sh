#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-pr.sh [OPTIONS]

Push the current branch and create a GitHub Pull Request.

This script is intended to be called by the Agentic-SDD /create-pr command.

Options:
  --issue <n>         Issue number (default: infer from branch name)
  --title <title>     PR title (default: GitHub Issue title)
  --body <text>       PR body text (default: 'Closes #<n>')
  --body-file <path>  PR body file path (overrides --body)
  --base <branch>     Base branch (default: origin/HEAD or 'main')
  --draft             Create PR as draft
  --dry-run           Print planned actions only
  -h, --help          Show help

Exit codes:
  0  Success
  2  Usage / precondition failure
EOF
}

eprint() { printf '%s\n' "$*" >&2; }

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    eprint "Missing command: $cmd"
    exit 2
  fi
}

fetch_remote_tracking_ref() {
  local repo_root="$1"
  local ref="$2"
  local remote_name=""
  local remote_prefix=""
  local branch=""
  while IFS= read -r remote_name; do
    [[ -n "$remote_name" ]] || continue
    remote_prefix="${remote_name}/"
    if [[ "$ref" != "$remote_prefix"* ]]; then
      continue
    fi
    branch="${ref#"$remote_prefix"}"
    if [[ -z "$branch" ]]; then
      return 0
    fi
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$ref"; then
      return 0
    fi
    if ! git -C "$repo_root" fetch --no-tags --quiet "$remote_name" "$branch"; then
      eprint "Failed to fetch latest base ref: $ref"
      eprint "Run 'git fetch $remote_name $branch' and retry /create-pr."
      exit 2
    fi
    return 0
  done < <(git -C "$repo_root" remote)
  return 0
}

normalize_base_branch_for_compare() {
  local repo_root="$1"
  local raw_ref="$2"
  local normalized="$raw_ref"
  local remote_name=""
  local remote_prefix=""
  local candidate_branch=""

  if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/$normalized"; then
    while IFS= read -r remote_name; do
      [[ -n "$remote_name" ]] || continue
      remote_prefix="${remote_name}/"
      if [[ "$normalized" != "$remote_prefix"* ]]; then
        continue
      fi
      candidate_branch="${normalized#"$remote_prefix"}"
      if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/${remote_name}/${candidate_branch}"; then
        normalized="$candidate_branch"
      fi
      break
    done < <(git -C "$repo_root" remote)
  fi

  printf '%s\n' "$normalized"
}

DRY_RUN=0
ISSUE=""
TITLE=""
BODY=""
BODY_FILE=""
BASE=""
DRAFT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      ISSUE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    --body-file)
      BODY_FILE="${2:-}"
      shift 2
      ;;
    --base)
      BASE="${2:-}"
      shift 2
      ;;
    --draft)
      DRAFT=1
      shift
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
      eprint "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

require_cmd git
require_cmd gh
require_cmd python3

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  eprint "Not in a git repository."
  exit 2
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ -z "$branch" ]]; then
  eprint "Failed to detect current branch."
  exit 2
fi

case "$branch" in
  main|master)
    eprint "Refusing to run on protected branch: $branch"
    exit 2
    ;;
esac

if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --quiet --staged; then
  eprint "Working tree is not clean. Commit or stash changes before creating a PR."
  exit 2
fi

origin_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"
if [[ -z "$origin_url" ]]; then
  eprint "Missing git remote: origin"
  exit 2
fi

if [[ -z "$ISSUE" ]]; then
  if [[ "$branch" =~ issue-([0-9]+) ]]; then
    ISSUE="${BASH_REMATCH[1]}"
  fi
fi

if [[ -z "$ISSUE" || ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  eprint "Issue number is required (use --issue <n> or name the branch with 'issue-<n>')."
  exit 2
fi

scope_id="issue-${ISSUE}"
review_root="$repo_root/.agentic-sdd/reviews/$scope_id"
current_run_file="$review_root/.current_run"

if [[ ! -f "$current_run_file" ]]; then
  eprint "Missing /review-cycle output (no .current_run): $current_run_file"
  eprint "Run /review-cycle ${scope_id} and ensure status is Approved/Approved with nits."
  exit 2
fi

run_id="$(cat "$current_run_file" 2>/dev/null || true)"
if [[ -z "$run_id" ]]; then
  eprint "Invalid .current_run (empty): $current_run_file"
  exit 2
fi

review_json="$review_root/$run_id/review.json"
if [[ ! -f "$review_json" ]]; then
  eprint "Missing review.json: $review_json"
  eprint "Run /review-cycle ${scope_id} again."
  exit 2
fi

review_meta="$review_root/$run_id/review-metadata.json"
if [[ ! -f "$review_meta" ]]; then
  eprint "Missing review metadata: $review_meta"
  eprint "Run /review-cycle ${scope_id} again to generate review-metadata.json."
  exit 2
fi

test_review_root="$repo_root/.agentic-sdd/test-reviews/$scope_id"
test_current_run_file="$test_review_root/.current_run"
if [[ ! -f "$test_current_run_file" ]]; then
  eprint "Missing /test-review output (no .current_run): $test_current_run_file"
  eprint "Run /test-review ${scope_id} and ensure status is Approved/Approved with nits."
  exit 2
fi

test_run_id="$(cat "$test_current_run_file" 2>/dev/null || true)"
if [[ -z "$test_run_id" ]]; then
  eprint "Invalid test-review .current_run (empty): $test_current_run_file"
  exit 2
fi
if [[ ! "$test_run_id" =~ ^[A-Za-z0-9._-]+$ || "$test_run_id" == "." || "$test_run_id" == ".." ]]; then
  eprint "Invalid test-review .current_run (unsafe run id): $test_current_run_file"
  eprint "Run /test-review ${scope_id} again."
  exit 2
fi

test_review_json="$test_review_root/$test_run_id/test-review.json"
if [[ ! -f "$test_review_json" ]]; then
  eprint "Missing test-review.json: $test_review_json"
  eprint "Run /test-review ${scope_id} again."
  exit 2
fi

test_review_meta="$test_review_root/$test_run_id/test-review-metadata.json"
if [[ ! -f "$test_review_meta" ]]; then
  eprint "Missing test-review metadata: $test_review_meta"
  eprint "Run /test-review ${scope_id} again to generate test-review-metadata.json."
  exit 2
fi

status="$(python3 - "$review_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(str(data.get('status') or ''))
PY
)"

if [[ "$status" != "Approved" && "$status" != "Approved with nits" ]]; then
  eprint "review.json is not passing: status='$status' (${review_json})"
  eprint "Fix findings/questions, then re-run /review-cycle ${scope_id}."
  exit 2
fi

test_status="$(python3 - "$test_review_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(str(data.get('status') or ''))
PY
)"

if [[ "$test_status" != "Approved" && "$test_status" != "Approved with nits" ]]; then
  eprint "test-review.json is not passing: status='$test_status' (${test_review_json})"
  eprint "Fix findings, then re-run /test-review ${scope_id}."
  exit 2
fi

meta_values="$(python3 - "$review_meta" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(str(data.get('head_sha') or ''))
print(str(data.get('base_ref') or ''))
print(str(data.get('base_sha') or ''))
print(str(data.get('diff_source') or ''))
PY
)"
meta_head_sha=""
meta_base_ref=""
meta_base_sha=""
meta_diff_source=""
{
  IFS= read -r meta_head_sha || true
  IFS= read -r meta_base_ref || true
  IFS= read -r meta_base_sha || true
  IFS= read -r meta_diff_source || true
} <<< "$meta_values"

if [[ -z "$meta_head_sha" ]]; then
  eprint "Invalid review metadata (missing head_sha): $review_meta"
  eprint "Run /review-cycle ${scope_id} again."
  exit 2
fi
if [[ "$meta_diff_source" != "range" ]]; then
  eprint "Invalid review metadata (diff_source must be 'range', got '$meta_diff_source'): $review_meta"
  eprint "Run /review-cycle ${scope_id} with DIFF_MODE=range on committed HEAD."
  exit 2
fi
if [[ -z "$meta_base_sha" ]]; then
  eprint "Invalid review metadata (diff_source=range requires base_sha): $review_meta"
  eprint "Run /review-cycle ${scope_id} again with DIFF_MODE=range."
  exit 2
fi

current_head_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$current_head_sha" ]]; then
  eprint "Failed to resolve current HEAD."
  exit 2
fi
if [[ "$current_head_sha" != "$meta_head_sha" ]]; then
  eprint "Current HEAD differs from reviewed HEAD."
  eprint "- current:  $current_head_sha"
  eprint "- reviewed: $meta_head_sha"
  eprint "Run /review-cycle ${scope_id} again on the current branch state."
  exit 2
fi

test_meta_values="$(python3 - "$test_review_meta" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(str(data.get('head_sha') or ''))
print(str(data.get('base_ref') or ''))
print(str(data.get('base_sha') or ''))
print(str(data.get('diff_mode') or ''))
PY
)"
test_meta_head_sha=""
test_meta_base_ref=""
test_meta_base_sha=""
test_meta_diff_mode=""
{
  IFS= read -r test_meta_head_sha || true
  IFS= read -r test_meta_base_ref || true
  IFS= read -r test_meta_base_sha || true
  IFS= read -r test_meta_diff_mode || true
} <<< "$test_meta_values"

if [[ -z "$test_meta_head_sha" ]]; then
  eprint "Invalid test-review metadata (missing head_sha): $test_review_meta"
  eprint "Run /test-review ${scope_id} again."
  exit 2
fi
if [[ "$test_meta_diff_mode" != "range" ]]; then
  eprint "Invalid test-review metadata (diff_mode must be 'range', got '$test_meta_diff_mode'): $test_review_meta"
  eprint "Run /test-review ${scope_id} with TEST_REVIEW_DIFF_MODE=range on committed HEAD."
  exit 2
fi
if [[ "$current_head_sha" != "$test_meta_head_sha" ]]; then
  eprint "Current HEAD differs from test-reviewed HEAD."
  eprint "- current:       $current_head_sha"
  eprint "- test-reviewed: $test_meta_head_sha"
  eprint "Run /test-review ${scope_id} again on the current branch state."
  exit 2
fi

if [[ -z "$test_meta_base_sha" ]]; then
  eprint "Invalid test-review metadata (diff_mode=range requires base_sha): $test_review_meta"
  eprint "Run /test-review ${scope_id} again."
  exit 2
fi

if [[ -n "$test_meta_base_sha" ]]; then
  effective_test_base_ref="${test_meta_base_ref:-main}"
  fetch_remote_tracking_ref "$repo_root" "$effective_test_base_ref"
  if ! git -C "$repo_root" rev-parse --verify "$effective_test_base_ref" >/dev/null 2>&1; then
    eprint "Base ref '$effective_test_base_ref' from test-review metadata was not found."
    eprint "Run /test-review ${scope_id} again."
    exit 2
  fi
  current_test_base_sha="$(git -C "$repo_root" rev-parse "$effective_test_base_ref")"
  if [[ "$current_test_base_sha" != "$test_meta_base_sha" ]]; then
    eprint "Base ref '$effective_test_base_ref' moved since /test-review."
    eprint "- current:       $current_test_base_sha"
    eprint "- test-reviewed: $test_meta_base_sha"
    eprint "Run /test-review ${scope_id} again against the latest base."
    exit 2
  fi
fi

if [[ -n "$meta_base_sha" ]]; then
  effective_base_ref="${meta_base_ref:-main}"
  fetch_remote_tracking_ref "$repo_root" "$effective_base_ref"
  if ! git -C "$repo_root" rev-parse --verify "$effective_base_ref" >/dev/null 2>&1; then
    eprint "Base ref '$effective_base_ref' from review metadata was not found."
    eprint "Run /review-cycle ${scope_id} again."
    exit 2
  fi
  current_base_sha="$(git -C "$repo_root" rev-parse "$effective_base_ref")"
  if [[ "$current_base_sha" != "$meta_base_sha" ]]; then
    eprint "Base ref '$effective_base_ref' moved since /review-cycle."
    eprint "- current:  $current_base_sha"
    eprint "- reviewed: $meta_base_sha"
    eprint "Run /review-cycle ${scope_id} again against the latest base."
    exit 2
  fi
fi

linked="$(gh issue develop --list "$ISSUE" 2>/dev/null || true)"
if [[ -z "$linked" ]]; then
  eprint "Issue has no linked branch (gh issue develop --list ${ISSUE} returned empty)."
  eprint "Create/link a branch before continuing (recommended: /worktree new --issue ${ISSUE} ...)."
  exit 2
fi

on_linked=0
while IFS= read -r b; do
  [[ -n "$b" ]] || continue
  linked_branch="${b%%[[:space:]]*}"
  if [[ "$linked_branch" == "$branch" ]]; then
    on_linked=1
    break
  fi
done <<< "$linked"

if [[ "$on_linked" -ne 1 ]]; then
  eprint "You are not on the linked branch for Issue #${ISSUE}."
  eprint "- current: $branch"
  eprint "- linked:"
  eprint "$linked"
  exit 2
fi

if [[ -z "$BASE" ]]; then
  base_ref="$(git -C "$repo_root" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$base_ref" ]]; then
    BASE="${base_ref##*/}"
  else
    BASE="main"
  fi
fi

if [[ -n "$test_meta_base_sha" ]]; then
  test_reviewed_base_branch="$(normalize_base_branch_for_compare "$repo_root" "${test_meta_base_ref:-main}")"
  if [[ "$BASE" != "$test_reviewed_base_branch" ]]; then
    eprint "PR base '$BASE' differs from test-reviewed base '$test_reviewed_base_branch'."
    eprint "Re-run /test-review for the target base, or use --base '$test_reviewed_base_branch'."
    exit 2
  fi
fi

if [[ -n "$meta_base_sha" ]]; then
  reviewed_base_branch="$(normalize_base_branch_for_compare "$repo_root" "${meta_base_ref:-main}")"
  if [[ "$BASE" != "$reviewed_base_branch" ]]; then
    eprint "PR base '$BASE' differs from reviewed base '$reviewed_base_branch'."
    eprint "Re-run /review-cycle for the target base, or use --base '$reviewed_base_branch'."
    exit 2
  fi
fi

if [[ -z "$TITLE" ]]; then
  issue_json="$(gh issue view "$ISSUE" --json title,url 2>/dev/null || true)"
  if [[ -z "$issue_json" ]]; then
    eprint "Failed to read Issue via gh: #$ISSUE"
    exit 2
  fi
  TITLE="$(python3 -c 'import json,sys; data=json.loads(sys.argv[1] or "{}"); print((data.get("title") or "").strip())' "$issue_json")"
  if [[ -z "$TITLE" ]]; then
    TITLE="Issue #${ISSUE}"
  fi
fi

if [[ -z "$BODY" && -z "$BODY_FILE" ]]; then
  BODY="Closes #${ISSUE}"
fi

eprint "Plan:"
eprint "- repo_root: $repo_root"
eprint "- branch: $branch"
eprint "- issue: #$ISSUE"
eprint "- base: $BASE"
eprint "- review: $review_json (status=$status)"
eprint "- review_meta: $review_meta (diff_source=${meta_diff_source:-unknown})"
eprint "- test_review: $test_review_json (status=$test_status)"
eprint "- test_review_meta: $test_review_meta"
eprint "- origin: $origin_url"

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

# 1) Push (keep stdout clean; PR URL is printed on stdout)
git -C "$repo_root" push -u origin HEAD >&2

# 2) If PR exists, show it and stop
pr_list_json="$(gh pr list --head "$branch" --state all --json number,url,state 2>/dev/null || true)"
if [[ -n "$pr_list_json" ]]; then
  pr_url="$(python3 -c 'import json,sys; data=json.loads(sys.argv[1] or "[]"); data=data if isinstance(data,list) else []; open_pr=next((x for x in data if isinstance(x,dict) and x.get("state")=="OPEN"), None); pick=open_pr or (data[0] if data else None); print(((pick or {}).get("url") or ""))' "$pr_list_json")"
  if [[ -n "$pr_url" ]]; then
    printf '%s\n' "$pr_url"
    exit 0
  fi
fi

# 3) Create PR
create_cmd=(gh pr create --title "$TITLE" --base "$BASE" --head "$branch")
if [[ "$DRAFT" -eq 1 ]]; then
  create_cmd+=(--draft)
fi

tmp_body=""
if [[ -n "$BODY_FILE" ]]; then
  if [[ ! -f "$BODY_FILE" ]]; then
    eprint "Body file not found: $BODY_FILE"
    exit 2
  fi
  create_cmd+=(--body-file "$BODY_FILE")
else
  tmp_body="$(mktemp -t agentic-sdd-pr-body.XXXXXX)"
  trap 'rm -f "$tmp_body"' EXIT
  printf '%s\n' "$BODY" > "$tmp_body"
  create_cmd+=(--body-file "$tmp_body")
fi

pr_url="$("${create_cmd[@]}")"
printf '%s\n' "$pr_url"
