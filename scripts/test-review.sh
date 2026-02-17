#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: test-review.sh <scope-id> [run-id] [--dry-run]

Run two-stage test review:
1) Preflight filter (deterministic command execution)
2) Post-filter quality checks (deterministic heuristics)

Environment:
  TEST_REVIEW_PREFLIGHT_COMMAND   Required command for preflight checks
  TEST_REVIEW_DIFF_MODE           auto|worktree|staged|range (default: auto)
  TEST_REVIEW_BASE_REF            Base ref when diff mode is range (default: origin/main)
  OUTPUT_ROOT                     Output root (default: <repo_root>/.agentic-sdd/test-reviews)

Output:
  <OUTPUT_ROOT>/<scope-id>/<run-id>/test-review.json
  <OUTPUT_ROOT>/<scope-id>/<run-id>/test-review-metadata.json
  <OUTPUT_ROOT>/<scope-id>/<run-id>/preflight.txt
  <OUTPUT_ROOT>/<scope-id>/<run-id>/diff-files.txt
EOF
}

eprint() { printf '%s\n' "$*" >&2; }

DRY_RUN=0
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      eprint "Unknown option: $1"
      usage
      exit 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ ${#args[@]} -lt 1 || ${#args[@]} -gt 2 ]]; then
  usage
  exit 2
fi

scope_id="${args[0]}"
run_id="${args[1]:-}"
if [[ ! "$scope_id" =~ ^[A-Za-z0-9._-]+$ || "$scope_id" == "." || "$scope_id" == ".." ]]; then
  eprint "Invalid scope-id: $scope_id"
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  eprint "Not in a git repository."
  exit 1
fi

output_root="${OUTPUT_ROOT:-${repo_root}/.agentic-sdd/test-reviews}"
scope_root="${output_root}/${scope_id}"
current_run_file="${scope_root}/.current_run"

if [[ -z "$run_id" && -f "$current_run_file" ]]; then
  candidate="$(cat "$current_run_file" 2>/dev/null || true)"
  if [[ "$candidate" =~ ^[A-Za-z0-9._-]+$ && "$candidate" != "." && "$candidate" != ".." ]]; then
    run_id="$candidate"
  fi
fi
if [[ -z "$run_id" ]]; then
  run_id="$(date +"%Y%m%d_%H%M%S")"
fi
if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  eprint "Invalid run-id: $run_id"
  exit 2
fi

run_dir="${scope_root}/${run_id}"
out_json="${run_dir}/test-review.json"
out_meta="${run_dir}/test-review-metadata.json"
out_preflight="${run_dir}/preflight.txt"
out_files="${run_dir}/diff-files.txt"

mkdir -p "$run_dir"

pref_cmd="${TEST_REVIEW_PREFLIGHT_COMMAND:-}"
if [[ -z "$pref_cmd" ]]; then
  eprint "TEST_REVIEW_PREFLIGHT_COMMAND is required."
  exit 2
fi

configured_diff_mode="${TEST_REVIEW_DIFF_MODE:-auto}"
diff_mode="$configured_diff_mode"
base_ref="${TEST_REVIEW_BASE_REF:-origin/main}"

collect_diff_files() {
  case "$configured_diff_mode" in
    auto)
      local worktree_files staged_files
      worktree_files="$(
        git diff --name-status
        git ls-files --others --exclude-standard | while IFS= read -r path; do
          [[ -n "$path" ]] || continue
          [[ "$path" == .agentic-sdd/* ]] && continue
          printf 'A\t%s\n' "$path"
        done
      )"
      staged_files="$(git diff --staged --name-status)"

      if [[ -n "$worktree_files" && -n "$staged_files" ]]; then
        eprint "TEST_REVIEW_DIFF_MODE=auto detected both staged and unstaged diffs. Choose TEST_REVIEW_DIFF_MODE=staged or worktree explicitly."
        return 2
      elif [[ -n "$worktree_files" ]]; then
        diff_mode="worktree"
        printf '%s\n' "$worktree_files"
      elif [[ -n "$staged_files" ]]; then
        diff_mode="staged"
        printf '%s\n' "$staged_files"
      else
        diff_mode="range"
        if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
          if [[ "$base_ref" == "origin/main" ]] && git rev-parse --verify main >/dev/null 2>&1; then
            base_ref="main"
          else
            eprint "Base ref not found for range mode: $base_ref"
            return 2
          fi
        fi
        git diff --name-status "$base_ref...HEAD"
      fi
      ;;
    worktree)
      diff_mode="worktree"
      {
        git diff --name-status HEAD
        git ls-files --others --exclude-standard | while IFS= read -r path; do
          [[ -n "$path" ]] || continue
          [[ "$path" == .agentic-sdd/* ]] && continue
          printf 'A\t%s\n' "$path"
        done
      }
      ;;
    staged)
      diff_mode="staged"
      git diff --staged --name-status
      ;;
    range)
      diff_mode="range"
      if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        if [[ "$base_ref" == "origin/main" ]] && git rev-parse --verify main >/dev/null 2>&1; then
          base_ref="main"
        else
          eprint "Base ref not found for range mode: $base_ref"
          return 2
        fi
      fi
      git diff --name-status "$base_ref...HEAD"
      ;;
    *)
      eprint "Invalid TEST_REVIEW_DIFF_MODE: $configured_diff_mode (use auto|worktree|staged|range)"
      return 2
      ;;
  esac
}

contains_focused_marker() {
  local path="$1"
  local focused_pattern='(^|[^[:alnum:]_])((it|describe|test)\.only|fit|fdescribe)\('
  case "$diff_mode" in
    worktree)
      [[ -f "$repo_root/$path" ]] || return 1
      grep -Eq "$focused_pattern" "$repo_root/$path"
      ;;
    staged)
      git cat-file -e ":$path" >/dev/null 2>&1 || return 1
      git show ":$path" | grep -Eq "$focused_pattern"
      ;;
    range)
      git cat-file -e "HEAD:$path" >/dev/null 2>&1 || return 1
      git show "HEAD:$path" | grep -Eq "$focused_pattern"
      ;;
    *)
      return 1
      ;;
  esac
}

should_scan_focused_marker() {
  local path="$1"
  case "$path" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_test_file_path() {
  local path="$1"

  case "$path" in
    scripts/tests/test-*.sh|test_*.py|*_test.py)
      return 0
      ;;
    docs/*|*.md)
      return 1
      ;;
  esac

  if [[ "$path" =~ \.(spec|test)(\.[^.]+)*\.([A-Za-z0-9]+)$ ]]; then
    local ext_lower
    ext_lower="$(printf '%s' "${BASH_REMATCH[3]}" | tr '[:upper:]' '[:lower:]')"
    case "$ext_lower" in
      md|markdown|txt|rst|adoc|yaml|yml|json|toml|lock|csv)
        return 1
        ;;
    esac
    return 0
  fi

  return 1
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  eprint "Plan:"
  eprint "- scope_id: $scope_id"
  eprint "- run_id: $run_id"
  eprint "- diff_mode: $configured_diff_mode"
  eprint "- base_ref: $base_ref"
  eprint "- preflight_command: $pref_cmd"
  eprint "- out_json: $out_json"
  exit 0
fi

set +e
bash -lc "$pref_cmd" >"$out_preflight" 2>&1
pref_exit=$?
set -e

set +e
collect_diff_files >"$out_files"
diff_exit=$?
set -e
if [[ "$diff_exit" -ne 0 ]]; then
  eprint "Failed to collect diff files."
  exit 2
fi

has_code_changes=0
has_test_changes=0
has_focused_tests=0
has_diff_entries=0

while IFS=$'\t' read -r status path1 path2; do
  [[ -n "$status" ]] || continue
  has_diff_entries=1
  f="$path1"
  if [[ "$status" == R* || "$status" == C* ]]; then
    f="$path2"
  fi
  [[ -n "$f" ]] || continue
  is_deleted=0
  is_test_file=0
  if [[ "$status" == D* ]]; then
    is_deleted=1
  fi

  if [[ "$f" == .agentic-sdd/* ]]; then
    :
  elif is_test_file_path "$f"; then
    is_test_file=1
    if [[ "$is_deleted" -eq 0 ]]; then
      has_test_changes=1
    fi
  elif [[ "$f" == docs/* || "$f" == *.md ]]; then
    :
  else
    has_code_changes=1
  fi

  if [[ "$is_deleted" -eq 0 && "$is_test_file" -eq 1 ]] && should_scan_focused_marker "$f" && contains_focused_marker "$f"; then
    has_focused_tests=1
  fi
done < "$out_files"

status="Approved"
overall="Preflight and deterministic test quality checks passed."
findings_json="[]"

if [[ "$pref_exit" -ne 0 ]]; then
  status="Blocked"
  overall="Preflight command failed."
  findings_json='[{"title":"Preflight failed","body":"TEST_REVIEW_PREFLIGHT_COMMAND returned non-zero.","priority":"P0"}]'
fi

if [[ "$status" != "Blocked" && "$has_focused_tests" -eq 1 ]]; then
  status="Blocked"
  overall="Focused/isolated test marker detected."
  findings_json='[{"title":"Focused test marker detected","body":"Remove .only/fit/fdescribe before proceeding.","priority":"P1"}]'
fi

if [[ "$status" != "Blocked" && "$has_code_changes" -eq 1 && "$has_test_changes" -eq 0 ]]; then
  status="Blocked"
  overall="Code changes detected without corresponding test changes."
  findings_json='[{"title":"Missing test updates","body":"Code changes exist but no test files changed.","priority":"P1"}]'
fi

if [[ "$status" != "Blocked" && "$has_diff_entries" -eq 0 ]]; then
  status="Blocked"
  overall="No diff entries found for test review scope."
  findings_json='[{"title":"No diff entries to review","body":"test-review produced no changed files for the selected diff mode/scope.","priority":"P1"}]'
fi

head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
base_sha=""
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  base_sha="$(git rev-parse "$base_ref")"
fi

python3 - "$out_json" "$scope_id" "$status" "$overall" "$findings_json" <<'PY'
import json
import sys

path, scope_id, status, overall, findings_json = sys.argv[1:6]
findings = json.loads(findings_json)
obj = {
    "schema_version": 1,
    "scope_id": scope_id,
    "status": status,
    "findings": findings,
    "overall_explanation": overall,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(obj, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

python3 - "$out_meta" "$scope_id" "$run_id" "$head_sha" "$base_ref" "$base_sha" "$diff_mode" <<'PY'
import json
import sys

path, scope_id, run_id, head_sha, base_ref, base_sha, diff_mode = sys.argv[1:8]
obj = {
    "schema_version": 1,
    "scope_id": scope_id,
    "run_id": run_id,
    "head_sha": head_sha,
    "base_ref": base_ref,
    "base_sha": base_sha,
    "diff_mode": diff_mode,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(obj, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

printf '%s' "$run_id" > "$current_run_file"

eprint "Wrote: $out_json"
eprint "Wrote: $out_meta"

if [[ "$status" == "Blocked" ]]; then
  exit 3
fi
