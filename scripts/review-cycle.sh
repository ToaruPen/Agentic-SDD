#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review-cycle.sh <scope-id> [run-id] [options]

Generate a review JSON (schema v3) via `codex exec --output-schema`.

Positional arguments:
  scope-id   Identifier for the reviewed scope (e.g. issue-123)
  run-id     Optional run identifier (default: reuse .current_run, else timestamp)

Options:
  --dry-run  Print the plan and exit without calling codex
  --model MODEL         Codex model override (takes precedence over env MODEL)
  --claude-model MODEL  Claude model override (takes precedence over env CLAUDE_MODEL)
  -h, --help Show help

Required environment:
  One of:
    SOT                  Manual source-of-truth (paths / links / summary)
    GH_ISSUE             GitHub issue number or URL (uses `gh issue view`)
    GH_ISSUE_BODY_FILE   Local file containing issue body (test/offline)
    SOT_FILES            Extra SoT files (repo-relative paths, shell-like quoting supported)

  And:
    TESTS                Short test summary (can be 'not run: reason')
                        OR set TEST_COMMAND to run tests and auto-populate TESTS.

  Optional environment:
  GH_ISSUE             GitHub issue number or URL
  GH_REPO              Repo for gh (OWNER/REPO)
  GH_INCLUDE_COMMENTS  1 to include comments in issue JSON (default: 0)
  GH_ISSUE_BODY_FILE   Local file containing issue body (test/offline)
  SOT_FILES            Extra SoT files (repo-relative paths, shell-like quoting supported)
  SOT_MAX_CHARS        Max chars for assembled SoT bundle (0 = no limit)
  TEST_COMMAND         Command to run tests (captures full output to tests.txt)
  TEST_STDERR_POLICY   warn|fail|ignore (default: warn). When TEST_COMMAND is set,
                     detect stderr output (and Vitest-style "stderr |" reports).
                     Writes tests.stderr alongside tests.txt.
  DIFF_MODE        range|staged|worktree|auto (default: range)
  BASE_REF         Base ref for range mode (default: origin/main; fallback: main)
  DIFF_FILE        Optional path to a diff file (overrides DIFF_MODE)
  OUTPUT_ROOT      Output root (default: <repo_root>/.agentic-sdd/reviews)
  SCHEMA_PATH      JSON schema path (default: <repo_root>/.agent/schemas/review.json)
  CONSTRAINTS      Additional constraints string (default: none)
  REVIEW_CYCLE_INCREMENTAL  0|1 (default: 1)
  REVIEW_CYCLE_CACHE_POLICY strict|balanced|off (default: balanced)
                   strict: reuse only Approved/Approved with nits
                   balanced: reuse all statuses on exact fingerprint match
                   off: disable reuse and always execute full review

  Engine selection:
  REVIEW_ENGINE    codex|claude (default: codex)

  Codex options (when REVIEW_ENGINE=codex):
  CODEX_BIN        codex binary (default: codex)
  MODEL            codex model (default: gpt-5.3-codex)
  REASONING_EFFORT high|medium|low (default: high)

  Claude options (when REVIEW_ENGINE=claude):
  CLAUDE_BIN       claude binary (default: claude)
  CLAUDE_MODEL     claude model (default: claude-opus-4-5-20250929)
                   Note: Claude Opus 4.5 has 200K token context window (half of Codex's 400K).
                   For large PRD+Epic+diff combinations, consider setting SOT_MAX_CHARS.

  Common options:
  EXEC_TIMEOUT_SEC Optional timeout in seconds (unset/empty => no timeout; uses timeout/gtimeout if available)
  MAX_DIFF_BYTES   Optional hard limit for diff.patch bytes (0/empty disables; min 1 when enabled)
  MAX_PROMPT_BYTES Optional hard limit for prompt.txt bytes (0/empty disables; min 1 when enabled)
  FORMAT_JSON      1 to pretty-format output JSON (default: 1)

Notes:
  - This script writes outputs under .agentic-sdd/ (recommended to gitignore).
  - DIFF_MODE=range compares BASE_REF...HEAD (default behavior).
  - In DIFF_MODE=auto, if both staged and worktree diffs are non-empty, this script
    fails and asks you to choose.
EOF
}

eprint() { printf '%s\n' "$*" >&2; }

DRY_RUN=0
model_cli_set=0
model_cli=""
claude_model_cli_set=0
claude_model_cli=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      # End of options marker. Treat the remaining args as positional.
      shift
      while [[ $# -gt 0 ]]; do
        args+=("$1")
        shift
      done
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --model)
      if [[ $# -lt 2 ]]; then
        eprint "Missing value for --model"
        usage
        exit 2
      fi
      model_cli_set=1
      model_cli="$2"
      shift 2
      ;;
    --model=*)
      model_cli_set=1
      model_cli="${1#*=}"
      shift
      ;;
    --claude-model)
      if [[ $# -lt 2 ]]; then
        eprint "Missing value for --claude-model"
        usage
        exit 2
      fi
      claude_model_cli_set=1
      claude_model_cli="$2"
      shift 2
      ;;
    --claude-model=*)
      claude_model_cli_set=1
      claude_model_cli="${1#*=}"
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
  eprint "Invalid scope-id: $scope_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')"
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  eprint "Not in a git repository; cannot locate repo root."
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

constraints="${CONSTRAINTS:-none}"
diff_mode="${DIFF_MODE:-range}"
base_ref="${BASE_REF:-origin/main}"
diff_file="${DIFF_FILE:-}"
output_root="${OUTPUT_ROOT:-${repo_root}/.agentic-sdd/reviews}"
schema_path="${SCHEMA_PATH:-${repo_root}/.agent/schemas/review.json}"

# Engine selection
review_engine="${REVIEW_ENGINE:-codex}"

# Validate engine selection early (before dry-run)
case "$review_engine" in
  codex|claude) ;;
  *)
    eprint "Invalid REVIEW_ENGINE: $review_engine (use codex|claude)"
    exit 2
    ;;
esac

# Codex options
codex_bin="${CODEX_BIN:-codex}"
if [[ "$model_cli_set" -eq 1 && -z "$model_cli" ]]; then
  eprint "Invalid --model: empty"
  exit 2
fi
model="${model_cli:-${MODEL:-gpt-5.3-codex}}"
effort="${REASONING_EFFORT:-high}"

# Claude options
claude_bin="${CLAUDE_BIN:-claude}"
if [[ "$claude_model_cli_set" -eq 1 && -z "$claude_model_cli" ]]; then
  eprint "Invalid --claude-model: empty"
  exit 2
fi
claude_model="${claude_model_cli:-${CLAUDE_MODEL:-claude-opus-4-5-20250929}}"

# Common options
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"
format_json="${FORMAT_JSON:-1}"
max_diff_bytes_raw="${MAX_DIFF_BYTES:-}"
max_prompt_bytes_raw="${MAX_PROMPT_BYTES:-}"

sot="${SOT:-}"
tests_summary="${TESTS:-}"
test_command="${TEST_COMMAND:-}"
test_stderr_policy="${TEST_STDERR_POLICY:-warn}"
tests_stderr_present=0
tests_stderr_summary="unknown"
tests_stderr_violation=0

gh_issue="${GH_ISSUE:-}"
gh_repo="${GH_REPO:-}"
gh_include_comments="${GH_INCLUDE_COMMENTS:-0}"
gh_issue_body_file="${GH_ISSUE_BODY_FILE:-}"
sot_files_raw="${SOT_FILES:-}"
sot_max_chars="${SOT_MAX_CHARS:-0}"

declare -a sot_files=()
if [[ -n "$sot_files_raw" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    eprint "python3 not found (required for SOT_FILES parsing)."
    exit 1
  fi

  if ! sot_files_parsed="$(python3 - "$sot_files_raw" <<'PY_SPLIT'
import sys
import shlex

raw = sys.argv[1]
try:
    parts = shlex.split(raw)
except ValueError as exc:
    print(f"Invalid SOT_FILES: {exc}", file=sys.stderr)
    sys.exit(2)

for item in parts:
    if item == "":
        continue
    print(item)
PY_SPLIT
  )"; then
    eprint "Invalid SOT_FILES; failed to parse shell-like list"
    exit 2
  fi

  while IFS= read -r parsed_item; do
    [[ -n "$parsed_item" ]] || continue
    sot_files+=("$parsed_item")
  done <<< "$sot_files_parsed"
fi

if [[ -z "$sot" && -z "$gh_issue" && -z "$gh_issue_body_file" && ${#sot_files[@]} -eq 0 ]]; then
  eprint "SoT is required. Set one of: SOT, GH_ISSUE, GH_ISSUE_BODY_FILE, SOT_FILES"
  exit 2
fi

if [[ ! "$sot_max_chars" =~ ^[0-9]+$ ]]; then
  eprint "Invalid SOT_MAX_CHARS: $sot_max_chars (expected integer)"
  exit 2
fi

scope_root="${output_root}/${scope_id}"
current_run_file="${scope_root}/.current_run"

if [[ -z "$run_id" && -f "$current_run_file" ]]; then
  candidate="$(cat "$current_run_file" 2>/dev/null || true)"
  if [[ "$candidate" =~ ^[A-Za-z0-9._-]+$ && "$candidate" != "." && "$candidate" != ".." ]]; then
    run_id="$candidate"
  else
    run_id=""
  fi
fi

if [[ -z "$run_id" ]]; then
  run_id="$(date +"%Y%m%d_%H%M%S")"
fi

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  eprint "Invalid run-id: $run_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')"
  exit 2
fi

run_dir="${scope_root}/${run_id}"
out_json="${run_dir}/review.json"
out_meta="${run_dir}/review-metadata.json"
out_diff="${run_dir}/diff.patch"
out_tests="${run_dir}/tests.txt"
out_tests_stderr="${run_dir}/tests.stderr"

out_sot="${run_dir}/sot.txt"
out_issue_json="${run_dir}/issue.json"
out_issue_body="${run_dir}/issue.txt"

diff_source=""
diff_detail=""
diff_base_sha=""
tests_exit_code=""
tests_fingerprint_input_sha256=""
diff_bytes=0
sot_bytes=0
prompt_bytes=0
engine_runtime_ms=0
# Internal compatibility token for incremental cache reuse.
# Bump when prompt composition or reuse eligibility semantics change.
script_semantics_version="v3"

review_cycle_incremental="${REVIEW_CYCLE_INCREMENTAL:-1}"
if [[ "$review_cycle_incremental" != "0" && "$review_cycle_incremental" != "1" ]]; then
  eprint "Invalid REVIEW_CYCLE_INCREMENTAL: $review_cycle_incremental (use 0|1)"
  exit 2
fi

review_cycle_cache_policy="${REVIEW_CYCLE_CACHE_POLICY:-balanced}"
case "$review_cycle_cache_policy" in
  strict|balanced|off) ;;
  *)
    eprint "Invalid REVIEW_CYCLE_CACHE_POLICY: $review_cycle_cache_policy (use strict|balanced|off)"
    exit 2
    ;;
esac

sha256_file() {
  local path="$1"
  python3 - "$path" <<'PY'
import hashlib
import sys

with open(sys.argv[1], "rb") as fh:
    print(hashlib.sha256(fh.read()).hexdigest())
PY
}

timeout_bin=""
if [[ -n "$exec_timeout_sec" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin="gtimeout"
  else
    eprint "EXEC_TIMEOUT_SEC set but no timeout/gtimeout found; running without timeout"
  fi
fi

ensure_run_dir() {
  mkdir -p "$run_dir"
}

parse_optional_byte_limit() {
  local name="$1"
  local raw="$2"
  local min_value="$3"
  local parsed=0
  if [[ -z "$raw" ]]; then
    printf '0\n'
    return 0
  fi
  if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
    eprint "Invalid ${name}: ${raw} (expected integer; use 0 to disable)"
    exit 2
  fi
  parsed=$((10#$raw))
  if (( parsed == 0 )); then
    printf '0\n'
    return 0
  fi
  if (( parsed < min_value )); then
    eprint "Invalid ${name}: ${raw} (minimum ${min_value} bytes when enabled; use 0 to disable)"
    exit 2
  fi
  printf '%s\n' "$parsed"
}

max_diff_bytes="$(parse_optional_byte_limit "MAX_DIFF_BYTES" "$max_diff_bytes_raw" 1)"
max_prompt_bytes="$(parse_optional_byte_limit "MAX_PROMPT_BYTES" "$max_prompt_bytes_raw" 1)"

git_ref_exists() {
  local ref="$1"
  git -C "$repo_root" rev-parse --verify "$ref" >/dev/null 2>&1
}

git_local_branch_exists() {
  local branch_ref="$1"
  git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_ref"
}

fetch_remote_tracking_ref() {
  local ref="$1"
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
    if git_local_branch_exists "$ref"; then
      return 0
    fi
    git -C "$repo_root" fetch --no-tags --quiet "$remote_name" "$branch"
    return $?
  done < <(git -C "$repo_root" remote)
  return 0
}

		write_tests() {
	  local exit_code=0
	  local reported_stderr=0
	  local tmp_tests_stdout=""

	  if [[ -n "$test_command" ]]; then
	    case "$test_stderr_policy" in
	      warn|fail|ignore) ;;
	      *)
	        eprint "Invalid TEST_STDERR_POLICY: $test_stderr_policy (use warn|fail|ignore)"
	        exit 2
	        ;;
	    esac

	    if [[ "$DRY_RUN" -eq 1 ]]; then
	      if [[ -z "$tests_summary" ]]; then
	        tests_summary="command: ${test_command} (not run: --dry-run)"
      fi
      tests_stderr_summary="not checked (dry-run)"
      return 0
	    fi

	    ensure_run_dir
	    tmp_tests_stdout="${run_dir}/tests.stdout.tmp.$$"
	    : > "$out_tests_stderr"
	    : > "$tmp_tests_stdout"
	    {
	      printf 'Command: %s\n' "$test_command"
	      printf 'Started: %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
	      printf '\n'
	    } > "$out_tests"

	    set +e
    env -u BASH_ENV bash -c "$test_command" >"$tmp_tests_stdout" 2>"$out_tests_stderr"
	    exit_code=$?
	    set -e
	    tests_exit_code="$exit_code"

	    tests_fingerprint_input_sha256="$(python3 - "$tmp_tests_stdout" "$out_tests_stderr" "$test_command" "$exit_code" "$test_stderr_policy" <<'PY'
import hashlib
import json
import sys

stdout_path = sys.argv[1]
stderr_path = sys.argv[2]
test_command = sys.argv[3]
exit_code = sys.argv[4]
stderr_policy = sys.argv[5]

with open(stdout_path, "rb") as fh:
    stdout_sha256 = hashlib.sha256(fh.read()).hexdigest()

with open(stderr_path, "rb") as fh:
    stderr_sha256 = hashlib.sha256(fh.read()).hexdigest()

payload = {
    "test_command": test_command,
    "exit_code": exit_code,
    "stderr_policy": stderr_policy,
    "stdout_sha256": stdout_sha256,
    "stderr_sha256": stderr_sha256,
}
encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
print(hashlib.sha256(encoded).hexdigest())
PY
)"

	    if grep -qE '^[[:space:]]*stderr [|]' "$tmp_tests_stdout"; then
	      reported_stderr=1
	      tests_stderr_present=1
	    fi

	    cat "$tmp_tests_stdout" >>"$out_tests"
	    if [[ -s "$out_tests_stderr" ]]; then
	      {
	        printf '\n'
	        printf '\n'
	        printf '[stderr]\n'
	      } >>"$out_tests"
	      cat "$out_tests_stderr" >>"$out_tests"
	    fi
	    rm -f "$tmp_tests_stdout" 2>/dev/null || true

	    if [[ -s "$out_tests_stderr" ]]; then
	      tests_stderr_present=1
	    fi

	    if [[ "$tests_stderr_present" -eq 1 ]]; then
	      if [[ "$reported_stderr" -eq 1 && -s "$out_tests_stderr" ]]; then
	        tests_stderr_summary="present (process-stderr + reported)"
      elif [[ "$reported_stderr" -eq 1 ]]; then
        tests_stderr_summary="present (reported)"
      else
        tests_stderr_summary="present (process-stderr)"
      fi
    else
      tests_stderr_summary="none"
    fi

    {
      printf '\n'
      printf 'Exit: %s\n' "$exit_code"
      printf 'Finished: %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
      printf 'Stderr: %s\n' "$tests_stderr_summary"
      printf 'Stderr-Policy: %s\n' "$test_stderr_policy"
    } >> "$out_tests"

    if [[ -z "$tests_summary" ]]; then
      if [[ "$exit_code" -eq 0 ]]; then
        if [[ "$tests_stderr_present" -eq 1 ]]; then
          tests_summary="command: ${test_command} (exit=0, stderr=present)"
        else
          tests_summary="command: ${test_command} (exit=0)"
        fi
      else
        if [[ "$tests_stderr_present" -eq 1 ]]; then
          tests_summary="command: ${test_command} (exit=${exit_code}, stderr=present)"
        else
          tests_summary="command: ${test_command} (exit=${exit_code})"
        fi
      fi
    fi

    if [[ "$tests_stderr_present" -eq 1 ]]; then
      case "$test_stderr_policy" in
        warn)
          eprint "WARNING: test command produced stderr output (exit=${exit_code}). See: $out_tests_stderr"
          ;;
        fail)
          tests_stderr_violation=1
          ;;
        ignore) ;;
      esac
    fi
  else
    if [[ -z "$tests_summary" ]]; then
      eprint "TEST_COMMAND is required for /review-cycle test verification."
      eprint "If you truly cannot run tests, set TESTS='not run: <reason>' explicitly."
      exit 2
    fi
    if [[ ! "$tests_summary" =~ ^[Nn][Oo][Tt][[:space:]]+[Rr][Uu][Nn]:[[:space:]]+.+$ ]]; then
      eprint "Invalid TESTS summary without TEST_COMMAND: '$tests_summary'"
      eprint "Set TEST_COMMAND to actually run tests, or use TESTS='not run: <reason>'."
      exit 2
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      return 0
    fi

    ensure_run_dir

    {
      printf 'Summary: %s\n' "$tests_summary"
      printf 'Recorded: %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
    } > "$out_tests"
    tests_exit_code=""
    tests_stderr_summary="not checked (no TEST_COMMAND)"
    tests_fingerprint_input_sha256="$(python3 - "$tests_summary" <<'PY'
import hashlib
import sys

summary = sys.argv[1]
print(hashlib.sha256(summary.encode("utf-8")).hexdigest())
PY
)"
  fi
}

write_diff() {
  if [[ -n "$diff_file" ]]; then
    if [[ ! -f "$diff_file" ]]; then
      eprint "Diff file not found: $diff_file"
      exit 2
    fi
    if [[ ! -s "$diff_file" ]]; then
      eprint "Diff is empty: $diff_file"
      exit 2
    fi
    diff_source="file"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      ensure_run_dir
      cp -p "$diff_file" "$out_diff"
    fi
    return 0
  fi

  local has_staged=0
  local has_worktree=0
  if ! git -C "$repo_root" diff --quiet --staged; then
    has_staged=1
  fi
  if ! git -C "$repo_root" diff --quiet; then
    has_worktree=1
  fi

  case "$diff_mode" in
    range)
      local base="$base_ref"
      if [[ "$has_staged" -eq 1 || "$has_worktree" -eq 1 ]]; then
        eprint "DIFF_MODE=range requires a clean working tree (no staged/unstaged changes)."
        eprint "Use DIFF_MODE=staged or DIFF_MODE=worktree for pre-commit local changes."
        exit 2
      fi
      if ! fetch_remote_tracking_ref "$base"; then
        # Preserve existing fallback behavior when origin/main cannot be fetched
        # and a local main exists.
        if [[ "$base" == "origin/main" ]] && ! git_ref_exists "$base" && git_ref_exists "main"; then
          base="main"
        else
          eprint "Failed to fetch latest base ref: $base"
          eprint "Run 'git fetch' and retry /review-cycle."
          exit 2
        fi
      fi
      if ! git_ref_exists "$base"; then
        if [[ "$base" == "origin/main" ]] && git_ref_exists "main"; then
          base="main"
        else
          eprint "Base ref not found for range diff: $base"
          exit 2
        fi
      fi
      diff_source="range"
      diff_detail="$base"
      diff_base_sha="$(git -C "$repo_root" rev-parse "$base" 2>/dev/null || true)"
      if [[ -z "$diff_base_sha" ]]; then
        eprint "Failed to resolve base SHA during range diff collection: $base"
        exit 2
      fi
      if git -C "$repo_root" diff --quiet "${base}...HEAD"; then
        eprint "Diff is empty (range: ${base}...HEAD)."
        exit 2
      fi
      if [[ "$DRY_RUN" -eq 0 ]]; then
        ensure_run_dir
        git -C "$repo_root" diff --no-color "${base}...HEAD" > "$out_diff"
      fi
      ;;
    staged)
      if [[ "$has_staged" -eq 0 ]]; then
        eprint "Diff is empty (staged)."
        exit 2
      fi
      diff_source="staged"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        ensure_run_dir
        git -C "$repo_root" diff --no-color --staged > "$out_diff"
      fi
      ;;
    worktree)
      if [[ "$has_worktree" -eq 0 ]]; then
        eprint "Diff is empty (worktree)."
        exit 2
      fi
      diff_source="worktree"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        ensure_run_dir
        git -C "$repo_root" diff --no-color > "$out_diff"
      fi
      ;;
    auto|"")
      if [[ "$has_staged" -eq 1 && "$has_worktree" -eq 1 ]]; then
        eprint "Both staged and worktree diffs are non-empty."
        eprint "Set DIFF_MODE=staged or DIFF_MODE=worktree (or set DIFF_FILE)."
        exit 2
      fi
      if [[ "$has_staged" -eq 1 ]]; then
        diff_source="staged"
        if [[ "$DRY_RUN" -eq 0 ]]; then
          ensure_run_dir
          git -C "$repo_root" diff --no-color --staged > "$out_diff"
        fi
      elif [[ "$has_worktree" -eq 1 ]]; then
        diff_source="worktree"
        if [[ "$DRY_RUN" -eq 0 ]]; then
          ensure_run_dir
          git -C "$repo_root" diff --no-color > "$out_diff"
        fi
      else
        eprint "Diff is empty (staged and worktree)."
        exit 2
      fi
      ;;
    *)
      eprint "Invalid DIFF_MODE: $diff_mode (use range|staged|worktree|auto)"
      exit 2
      ;;
  esac

  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ ! -s "$out_diff" ]]; then
      if [[ "$diff_source" == "range" && -n "$diff_detail" ]]; then
        eprint "Diff is empty (range: ${diff_detail}...HEAD)."
      else
        eprint "Diff is empty after collection: $out_diff"
      fi
      exit 2
    fi
  fi
}

print_plan() {
  eprint "Plan:"
  eprint "- repo_root: $repo_root"
  eprint "- scope_id: $scope_id"
  eprint "- run_id: $run_id"
  eprint "- schema_path: $schema_path"
  eprint "- out_dir: $run_dir"
  eprint "- out_json: $out_json"
  eprint "- out_meta: $out_meta"
  eprint "- out_diff: $out_diff"
  eprint "- out_tests: $out_tests"
  eprint "- out_tests_stderr: $out_tests_stderr"
  eprint "- out_sot: $out_sot"
  eprint "- diff_mode: $diff_mode"
  eprint "- base_ref: $base_ref"
  if [[ -n "$diff_source" ]]; then
    eprint "- diff_source: $diff_source"
  fi
  if [[ -n "$diff_detail" ]]; then
    eprint "- diff_detail: $diff_detail"
  fi
  if [[ -n "$diff_file" ]]; then
    eprint "- diff_file: $diff_file"
  fi
  eprint "- review_engine: $review_engine"
  case "$review_engine" in
    codex)
      eprint "- codex_bin: $codex_bin"
      eprint "- model: $model"
      eprint "- reasoning_effort: $effort"
      ;;
    claude)
      eprint "- claude_bin: $claude_bin"
      eprint "- claude_model: $claude_model"
      ;;
  esac
  if [[ -n "$exec_timeout_sec" ]]; then
    eprint "- exec_timeout_sec: $exec_timeout_sec"
  fi
  eprint "- constraints: $constraints"
  eprint "- max_diff_bytes: $max_diff_bytes"
  eprint "- max_prompt_bytes: $max_prompt_bytes"
  eprint "- review_cycle_incremental: $review_cycle_incremental"
  eprint "- review_cycle_cache_policy: $review_cycle_cache_policy"
  if [[ -n "$gh_issue" ]]; then
    eprint "- gh_issue: $gh_issue"
    if [[ -n "$gh_repo" ]]; then
      eprint "- gh_repo: $gh_repo"
    fi
    eprint "- gh_include_comments: $gh_include_comments"
  fi
  if [[ -n "$gh_issue_body_file" ]]; then
    eprint "- gh_issue_body_file: $gh_issue_body_file"
  fi
  if [[ ${#sot_files[@]} -gt 0 ]]; then
    eprint "- sot_files: ${sot_files[*]}"
  fi
  eprint "- sot_max_chars: $sot_max_chars"
  if [[ -n "$sot" ]]; then
    eprint "- sot: $sot"
  fi
  if [[ -n "$test_command" ]]; then
    eprint "- test_command: $test_command"
  fi
  eprint "- tests_summary: $tests_summary"
  eprint "- tests_stderr_policy: $test_stderr_policy"
  eprint "- tests_stderr: $tests_stderr_summary"
}

write_sot() {
  local issue_json_arg=""
  local issue_body_arg=""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  ensure_run_dir

  if [[ -n "$gh_issue" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
      eprint "gh not found (required for GH_ISSUE)"
      exit 1
    fi

    fields="title,url,body,number"
    if [[ "$gh_include_comments" == "1" ]]; then
      fields="title,url,body,number,comments"
    fi

    gh_cmd=(gh issue view "$gh_issue" --json "$fields")
    if [[ -n "$gh_repo" ]]; then
      gh_cmd=(gh -R "$gh_repo" issue view "$gh_issue" --json "$fields")
    fi

    "${gh_cmd[@]}" > "$out_issue_json"
    issue_json_arg="$out_issue_json"
  fi

  if [[ -n "$gh_issue_body_file" ]]; then
    if [[ ! -f "$gh_issue_body_file" ]]; then
      eprint "GH_ISSUE_BODY_FILE not found: $gh_issue_body_file"
      exit 2
    fi
    cp -p "$gh_issue_body_file" "$out_issue_body"
    issue_body_arg="$out_issue_body"
  fi

  if [[ -z "$issue_json_arg" && -z "$issue_body_arg" ]]; then
    issue_body_arg=""
  fi

  assemble_cmd=(python3 "$script_dir/assemble-sot.py" --repo-root "$repo_root" --manual-sot "$sot" --max-chars "$sot_max_chars")
  if [[ -n "$issue_json_arg" ]]; then
    assemble_cmd+=(--issue-json "$issue_json_arg")
  fi
  if [[ -n "$issue_body_arg" ]]; then
    assemble_cmd+=(--issue-body-file "$issue_body_arg")
  fi

  if [[ ${#sot_files[@]} -gt 0 ]]; then
    for f in "${sot_files[@]}"; do
      assemble_cmd+=(--sot-file "$f")
    done
  fi

  "${assemble_cmd[@]}" > "$out_sot"
}

write_diff
write_tests
write_sot

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_plan
  exit 0
fi

diff_bytes="$(wc -c < "$out_diff" | tr -d ' ')"
sot_bytes="$(wc -c < "$out_sot" | tr -d ' ')"

if (( max_diff_bytes > 0 && diff_bytes > max_diff_bytes )); then
  eprint "Diff bytes exceeded MAX_DIFF_BYTES: diff_bytes=$diff_bytes max=$max_diff_bytes"
  eprint "Narrow the review input scope (DIFF_FILE/DIFF_MODE/include/exclude) and retry."
  exit 2
fi

if [[ "$tests_stderr_violation" -eq 1 ]]; then
  eprint "TEST_STDERR_POLICY=fail: failing due to stderr output from test command."
  eprint "See: $out_tests_stderr"
  exit 3
fi

if [[ ! -f "$schema_path" ]]; then
  eprint "Schema not found: $schema_path"
  eprint "Expected this repo to have .agent/schemas/review.json installed."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  eprint "python3 not found (required for validation)."
  exit 1
fi

head_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$head_sha" ]]; then
  eprint "Failed to resolve current HEAD SHA for review metadata."
  exit 1
fi

meta_base_ref=""
meta_base_sha=""
if [[ "$diff_source" == "range" && -n "$diff_detail" ]]; then
  meta_base_ref="$diff_detail"
  meta_base_sha="$diff_base_sha"
  if [[ -z "$meta_base_sha" ]]; then
    eprint "Failed to resolve pinned base SHA for review metadata: $meta_base_ref"
    exit 1
  fi
fi

diff_sha256="$(sha256_file "$out_diff")"
sot_fingerprint="$(sha256_file "$out_sot")"
tests_fingerprint="$(python3 - "$out_tests" "$tests_summary" "$tests_stderr_summary" "$test_stderr_policy" "$tests_exit_code" "$tests_fingerprint_input_sha256" <<'PY'
import hashlib
import json
import sys

_tests_path = sys.argv[1]
tests_summary = sys.argv[2]
tests_stderr_summary = sys.argv[3]
tests_stderr_policy = sys.argv[4]
tests_exit_code = sys.argv[5]
tests_input_sha256 = sys.argv[6]

payload = {
    "tests_summary": tests_summary,
    "tests_stderr_summary": tests_stderr_summary,
    "tests_stderr_policy": tests_stderr_policy,
    "tests_exit_code": tests_exit_code,
    "tests_input_sha256": tests_input_sha256,
}
encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
print(hashlib.sha256(encoded).hexdigest())
PY
)"
schema_sha256="$(sha256_file "$schema_path")"

tmp_json="${out_json}.tmp.$$"
tmp_prompt="${run_dir}/prompt.txt"

engine_version_output=""
case "$review_engine" in
  codex)
    engine_version_output="$("$codex_bin" --version 2>/dev/null || true)"
    ;;
  claude)
    engine_version_output="$("$claude_bin" --version 2>/dev/null || true)"
    ;;
esac
engine_version_available=0
if [[ -n "$engine_version_output" ]]; then
  engine_version_available=1
fi

engine_fingerprint=""

reuse_candidate_run=""
reuse_candidate_meta=""
reuse_candidate_json=""
reuse_eligible=0
reuse_reason="no-previous-run"
reused=0
reused_from_run=""

if [[ -f "$current_run_file" ]]; then
  candidate_run="$(cat "$current_run_file" 2>/dev/null || true)"
  if [[ "$candidate_run" =~ ^[A-Za-z0-9._-]+$ && "$candidate_run" != "." && "$candidate_run" != ".." ]]; then
    candidate_meta="$scope_root/$candidate_run/review-metadata.json"
    candidate_json="$scope_root/$candidate_run/review.json"
    if [[ -f "$candidate_meta" && -f "$candidate_json" ]]; then
      reuse_candidate_run="$candidate_run"
      reuse_candidate_meta="$candidate_meta"
      reuse_candidate_json="$candidate_json"
    else
      reuse_reason="candidate-artifacts-missing"
    fi
  else
    reuse_reason="candidate-run-invalid"
  fi
fi

if [[ "$review_cycle_incremental" == "1" && "$review_cycle_cache_policy" == "off" ]]; then
  reuse_reason="cache-policy-off"
fi

if [[ "$review_cycle_incremental" == "1" && "$review_cycle_cache_policy" != "off" && -n "$reuse_candidate_meta" ]]; then
  reuse_state_fast="$(python3 - "$reuse_candidate_meta" "$reuse_candidate_json" "$head_sha" "$meta_base_ref" "$meta_base_sha" "$diff_source" "$diff_sha256" "$sot_fingerprint" "$tests_fingerprint" "$engine_version_available" "$review_engine" "$model" "$effort" "$claude_model" "$schema_sha256" "$constraints" "$engine_version_output" "$script_semantics_version" "$review_cycle_cache_policy" "$max_prompt_bytes" <<'PY'
import json
import sys

meta_path = sys.argv[1]
review_path = sys.argv[2]
curr_head = sys.argv[3]
curr_base_ref = sys.argv[4]
curr_base_sha = sys.argv[5]
curr_diff_source = sys.argv[6]
curr_diff_sha256 = sys.argv[7]
curr_sot_fp = sys.argv[8]
curr_tests_fp = sys.argv[9]
curr_engine_version_available = sys.argv[10] == "1"
curr_review_engine = sys.argv[11]
curr_codex_model = sys.argv[12]
curr_reasoning_effort = sys.argv[13]
curr_claude_model = sys.argv[14]
curr_schema_sha256 = sys.argv[15]
curr_constraints = sys.argv[16]
curr_engine_version_output = sys.argv[17]
curr_script_semantics_version = sys.argv[18]
curr_cache_policy = sys.argv[19]
curr_max_prompt_bytes = int(sys.argv[20])

def out(eligible: bool, reason: str, engine_fingerprint: str = "", prompt_bytes=None) -> None:
    print("eligible=1" if eligible else "eligible=0")
    print(f"reason={reason}")
    if engine_fingerprint:
        print(f"engine_fingerprint={engine_fingerprint}")
    if prompt_bytes is not None:
        print(f"prompt_bytes={prompt_bytes}")

try:
    with open(meta_path, "r", encoding="utf-8") as fh:
        meta = json.load(fh)
except Exception:
    out(False, "metadata-unreadable")
    raise SystemExit(0)

try:
    with open(review_path, "r", encoding="utf-8") as fh:
        review = json.load(fh)
except Exception:
    out(False, "review-unreadable")
    raise SystemExit(0)

required = [
    "head_sha",
    "base_ref",
    "base_sha",
    "diff_source",
    "diff_sha256",
    "sot_fingerprint",
    "tests_fingerprint",
    "engine_fingerprint",
    "review_engine",
    "codex_model",
    "reasoning_effort",
    "claude_model",
    "schema_sha256",
    "constraints",
    "engine_version_output",
    "script_semantics_version",
]
for key in required:
    value = meta.get(key)
    if not isinstance(value, str):
        out(False, f"missing-{key}")
        raise SystemExit(0)

if meta.get("schema_version") != 1:
    out(False, "schema-version-mismatch")
    raise SystemExit(0)

if not curr_engine_version_available:
    out(False, "engine-version-unavailable")
    raise SystemExit(0)

if meta.get("engine_version_available") is not True:
    out(False, "cached-engine-version-unavailable")
    raise SystemExit(0)

status = str(review.get("status") or "")
if curr_cache_policy == "strict":
    allowed_statuses = {"Approved", "Approved with nits"}
    hit_reason = "cache-hit-strict"
elif curr_cache_policy == "balanced":
    allowed_statuses = {"Approved", "Approved with nits", "Blocked", "Question"}
    hit_reason = "cache-hit-balanced"
else:
    out(False, "invalid-cache-policy")
    raise SystemExit(0)

if status not in allowed_statuses:
    out(False, f"status-not-reusable-{curr_cache_policy}")
    raise SystemExit(0)

if meta.get("review_completed") is not True:
    out(False, "review-not-completed")
    raise SystemExit(0)

tests_exit_code = meta.get("tests_exit_code")
if tests_exit_code is not None and tests_exit_code != 0:
    out(False, "tests-exit-nonzero")
    raise SystemExit(0)

meta_prompt_bytes = meta.get("prompt_bytes")
if curr_max_prompt_bytes > 0:
    if not isinstance(meta_prompt_bytes, int) or meta_prompt_bytes < 0:
        out(False, "prompt-bytes-missing")
        raise SystemExit(0)
    if meta_prompt_bytes > curr_max_prompt_bytes:
        out(False, "prompt-bytes-exceeded")
        raise SystemExit(0)

checks = [
    ("head_sha", curr_head),
    ("base_ref", curr_base_ref),
    ("base_sha", curr_base_sha),
    ("diff_source", curr_diff_source),
    ("diff_sha256", curr_diff_sha256),
    ("sot_fingerprint", curr_sot_fp),
    ("tests_fingerprint", curr_tests_fp),
    ("review_engine", curr_review_engine),
    ("codex_model", curr_codex_model if curr_review_engine == "codex" else ""),
    ("reasoning_effort", curr_reasoning_effort if curr_review_engine == "codex" else ""),
    ("claude_model", curr_claude_model if curr_review_engine == "claude" else ""),
    ("schema_sha256", curr_schema_sha256),
    ("constraints", curr_constraints),
    ("engine_version_output", curr_engine_version_output),
    ("script_semantics_version", curr_script_semantics_version),
]

for key, expected in checks:
    if str(meta.get(key)) != expected:
        out(False, f"{key}-mismatch")
        raise SystemExit(0)

if not isinstance(meta_prompt_bytes, int) or meta_prompt_bytes < 0:
    meta_prompt_bytes = 0

out(True, hit_reason, str(meta.get("engine_fingerprint")), meta_prompt_bytes)
PY
)"
  reuse_eligible=0
  reuse_reason="unknown"
  cached_engine_fingerprint=""
  cached_prompt_bytes=0
  while IFS= read -r line; do
    case "$line" in
      eligible=1) reuse_eligible=1 ;;
      eligible=0) reuse_eligible=0 ;;
      reason=*) reuse_reason="${line#reason=}" ;;
      engine_fingerprint=*) cached_engine_fingerprint="${line#engine_fingerprint=}" ;;
      prompt_bytes=*) cached_prompt_bytes="${line#prompt_bytes=}" ;;
    esac
  done <<< "$reuse_state_fast"

  if [[ "$reuse_eligible" -eq 1 ]]; then
    if python3 "$script_dir/validate-review-json.py" "$reuse_candidate_json" --scope-id "$scope_id" >/dev/null 2>&1; then
      ensure_run_dir
      if [[ "$reuse_candidate_json" != "$out_json" ]]; then
        cp -p "$reuse_candidate_json" "$out_json"
      fi
      reused=1
      reused_from_run="$reuse_candidate_run"
      engine_fingerprint="$cached_engine_fingerprint"
      prompt_bytes="$cached_prompt_bytes"
    else
      reuse_eligible=0
      reuse_reason="candidate-review-invalid"
    fi
  fi
fi

if [[ "$reused" -eq 0 ]]; then
  # Build prompt
  {
    cat <<'PROMPT'
You are a code reviewer.

Output JSON only. Your output MUST validate against the provided JSON schema.

Review rules:
- Only flag issues introduced by this diff (do not flag pre-existing issues).
- Only flag issues the author would likely fix if aware (meaningful impact).
- Be concrete; avoid speculation; explain impact.
- Ignore trivial style unless it obscures meaning or violates documented standards.

Priority:
- P0: must-fix (correctness/security/data-loss)
- P1: should-fix (likely bug / broken tests / risky behavior)
- P2: improvement (maintainability/perf minor)
- P3: nit (small clarity)

Status rules:
- Approved: findings=[] and questions=[]
- Approved with nits: findings may exist but must not include P0/P1; questions=[]
- Blocked: must include at least one P0/P1 finding
- Question: must include at least one question

Finding requirements:
- body: 1 short paragraph (Markdown allowed)
- code_location.repo_relative_path: repo-relative; do not use absolute paths
- code_location.line_range: keep as small as possible; overlap the diff

Do not output these keys (they are intentionally omitted for determinism):

- facet
- facet_slug
- uncertainty
- overall_correctness
- overall_confidence_score
- findings[].confidence_score

Output requirements:
- scope_id must match the "Scope-ID" value below
- questions must be an array (use [] when none)
- No markdown fences, no extra prose.
PROMPT
    printf 'Schema-Version: 3\n'
    printf 'Scope-ID: %s\n' "$scope_id"
    printf 'SoT:\n'
    cat "$out_sot"
    printf '\n'
    printf 'Tests: %s\n' "$tests_summary"
    printf 'Tests-Stderr: %s\n' "$tests_stderr_summary"
    printf 'Tests-Stderr-Policy: %s\n' "$test_stderr_policy"
    printf 'Constraints: %s\n' "$constraints"
    printf 'Diff:\n'
    cat "$out_diff"
  } > "$tmp_prompt"

  prompt_bytes="$(wc -c < "$tmp_prompt" | tr -d ' ')"
  if (( max_prompt_bytes > 0 && prompt_bytes > max_prompt_bytes )); then
    eprint "Prompt bytes exceeded MAX_PROMPT_BYTES: prompt_bytes=$prompt_bytes max=$max_prompt_bytes"
    eprint "Reduce SoT/diff input size and retry."
    exit 2
  fi

  case "$review_engine" in
    codex)
      if ! command -v "$codex_bin" >/dev/null 2>&1; then
        eprint "codex not found: $codex_bin"
        exit 1
      fi
      ;;
    claude)
      if ! command -v "$claude_bin" >/dev/null 2>&1; then
        eprint "claude not found: $claude_bin"
        exit 1
      fi
      ;;
    *)
      eprint "Invalid REVIEW_ENGINE: $review_engine (use codex|claude)"
      exit 2
      ;;
  esac

  prompt_sha256="$(sha256_file "$tmp_prompt")"
  engine_fingerprint="$(python3 - "$review_engine" "$model" "$effort" "$claude_model" "$schema_sha256" "$constraints" "$engine_version_output" "$prompt_sha256" "$script_semantics_version" <<'PY'
import hashlib
import json
import sys

engine = sys.argv[1]
codex_model = sys.argv[2]
effort = sys.argv[3]
claude_model = sys.argv[4]
schema_sha256 = sys.argv[5]
constraints = sys.argv[6]
engine_version_output = sys.argv[7]
prompt_sha256 = sys.argv[8]
script_semantics_version = sys.argv[9]
material = {
    "review_engine": engine,
    "codex_model": codex_model if engine == "codex" else "",
    "reasoning_effort": effort if engine == "codex" else "",
    "claude_model": claude_model if engine == "claude" else "",
    "schema_sha256": schema_sha256,
    "constraints": constraints,
    "engine_version_output": engine_version_output,
    "prompt_sha256": prompt_sha256,
    "script_semantics_version": script_semantics_version,
}
encoded = json.dumps(material, ensure_ascii=False, sort_keys=True).encode("utf-8")
print(hashlib.sha256(encoded).hexdigest())
PY
)"
fi

if [[ "$reused" -eq 0 ]]; then
  engine_start_ms="$(python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
)"

  case "$review_engine" in
    codex)
      cmd=(
        "$codex_bin" exec
        --sandbox read-only
        -m "$model"
        -c "reasoning.effort=\"${effort}\""
        --output-last-message "$tmp_json"
        --output-schema "$schema_path"
        -
      )

      if [[ -n "$exec_timeout_sec" && -n "$timeout_bin" ]]; then
        cmd=("$timeout_bin" "$exec_timeout_sec" "${cmd[@]}")
      fi

      "${cmd[@]}" < "$tmp_prompt"
      ;;
    claude)
      schema_content="$(python3 -c "
import json
import sys
with open('$schema_path', 'r', encoding='utf-8') as f:
    schema = json.load(f)
schema.pop('\$schema', None)
print(json.dumps(schema, ensure_ascii=False))
")"

      cmd=(
        "$claude_bin" -p
        --model "$claude_model"
        --json-schema "$schema_content"
        --output-format json
        --betas interleaved-thinking
      )

      if [[ -n "$exec_timeout_sec" && -n "$timeout_bin" ]]; then
        cmd=("$timeout_bin" "$exec_timeout_sec" "${cmd[@]}")
      fi

      tmp_claude_out="${tmp_json}.claude.$$"
      "${cmd[@]}" < "$tmp_prompt" > "$tmp_claude_out"

      python3 -c "
import json
import sys

try:
    with open('$tmp_claude_out', 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f'Failed to parse Claude output: {e}', file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print('Claude output is not a JSON object', file=sys.stderr)
    sys.exit(1)

is_wrapped = 'type' in data and data.get('type') == 'result'

if is_wrapped:
    subtype = data.get('subtype', '')
    if subtype and subtype != 'success':
        errors = data.get('errors', [])
        print(f'Claude returned error: {subtype}', file=sys.stderr)
        if errors:
            for err in errors:
                print(f'  {err}', file=sys.stderr)
        sys.exit(1)

    structured = data.get('structured_output')
    if structured is None:
        print('Claude output missing structured_output field', file=sys.stderr)
        print('Full response:', file=sys.stderr)
        print(json.dumps(data, indent=2), file=sys.stderr)
        sys.exit(1)
    output = structured
else:
    output = data

with open('$tmp_json', 'w', encoding='utf-8') as f:
    json.dump(output, f, ensure_ascii=False)
"
      extract_exit=$?
      rm -f "$tmp_claude_out"

      if [[ $extract_exit -ne 0 ]]; then
        eprint "Failed to extract structured_output from Claude response"
        exit 1
      fi
      ;;
  esac

  engine_end_ms="$(python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
)"
  engine_runtime_ms="$((engine_end_ms - engine_start_ms))"
  if [[ "$engine_runtime_ms" -lt 0 ]]; then
    engine_runtime_ms=0
  fi

  if [[ ! -f "$tmp_json" || ! -s "$tmp_json" ]]; then
    eprint "$review_engine did not produce output: $tmp_json"
    exit 1
  fi

  mv "$tmp_json" "$out_json"
fi

validate_args=("$out_json" --scope-id "$scope_id")
if [[ "$format_json" != "0" ]]; then
  validate_args+=(--format)
fi
python3 "$script_dir/validate-review-json.py" "${validate_args[@]}"

non_reuse_reason=""
if [[ "$reused" -eq 0 ]]; then
  if [[ "$review_cycle_incremental" != "1" ]]; then
    non_reuse_reason="incremental-disabled"
  else
    non_reuse_reason="$reuse_reason"
  fi
fi

python3 - "$out_meta" "$scope_id" "$run_id" "$diff_source" "$meta_base_ref" "$meta_base_sha" "$head_sha" "$diff_sha256" "$sot_fingerprint" "$tests_fingerprint" "$engine_fingerprint" "$engine_version_available" "$review_cycle_incremental" "$review_cycle_cache_policy" "$reuse_eligible" "$reused" "$reuse_reason" "$non_reuse_reason" "$reused_from_run" "$tests_exit_code" "$prompt_bytes" "$sot_bytes" "$diff_bytes" "$engine_runtime_ms" "$review_engine" "$model" "$effort" "$claude_model" "$schema_sha256" "$constraints" "$engine_version_output" "$script_semantics_version" <<'PY'
import datetime
import json
import os
import sys

out_meta = sys.argv[1]
scope_id = sys.argv[2]
run_id = sys.argv[3]
diff_source = sys.argv[4]
base_ref = sys.argv[5]
base_sha = sys.argv[6]
head_sha = sys.argv[7]
diff_sha256 = sys.argv[8]
sot_fingerprint = sys.argv[9]
tests_fingerprint = sys.argv[10]
engine_fingerprint = sys.argv[11]
engine_version_available = sys.argv[12] == "1"
incremental_enabled = sys.argv[13] == "1"
cache_policy = sys.argv[14]
reuse_eligible = sys.argv[15] == "1"
reused = sys.argv[16] == "1"
reuse_reason = sys.argv[17]
non_reuse_reason = sys.argv[18]
reused_from_run = sys.argv[19]
tests_exit_code_raw = sys.argv[20]
prompt_bytes_raw = sys.argv[21]
sot_bytes_raw = sys.argv[22]
diff_bytes_raw = sys.argv[23]
engine_runtime_ms_raw = sys.argv[24]
review_engine = sys.argv[25]
model = sys.argv[26]
reasoning_effort = sys.argv[27]
claude_model = sys.argv[28]
schema_sha256 = sys.argv[29]
constraints = sys.argv[30]
engine_version_output = sys.argv[31]
script_semantics_version = sys.argv[32]

tests_exit_code = None
if tests_exit_code_raw:
    try:
        tests_exit_code = int(tests_exit_code_raw)
    except ValueError:
        tests_exit_code = None

def parse_int(raw: str, default: int = 0) -> int:
    try:
        return int(raw)
    except (TypeError, ValueError):
        return default

payload = {
    "schema_version": 1,
    "scope_id": scope_id,
    "run_id": run_id,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "diff_source": diff_source,
    "base_ref": base_ref,
    "base_sha": base_sha,
    "head_sha": head_sha,
    "diff_sha256": diff_sha256,
    "sot_fingerprint": sot_fingerprint,
    "tests_fingerprint": tests_fingerprint,
    "engine_fingerprint": engine_fingerprint,
    "review_engine": review_engine,
    "codex_model": model if review_engine == "codex" else "",
    "reasoning_effort": reasoning_effort if review_engine == "codex" else "",
    "claude_model": claude_model if review_engine == "claude" else "",
    "schema_sha256": schema_sha256,
    "constraints": constraints,
    "engine_version_output": engine_version_output,
    "script_semantics_version": script_semantics_version,
    "engine_version_available": engine_version_available,
    "incremental_enabled": incremental_enabled,
    "cache_policy": cache_policy,
    "reuse_eligible": reuse_eligible,
    "reused": reused,
    "reuse_reason": reuse_reason,
    "non_reuse_reason": non_reuse_reason,
    "reused_from_run": reused_from_run,
    "review_completed": True,
    "tests_exit_code": tests_exit_code,
    "prompt_bytes": parse_int(prompt_bytes_raw),
    "sot_bytes": parse_int(sot_bytes_raw),
    "diff_bytes": parse_int(diff_bytes_raw),
    "engine_runtime_ms": parse_int(engine_runtime_ms_raw),
}

os.makedirs(os.path.dirname(out_meta), exist_ok=True)
with open(out_meta, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

tmp_run_file="${current_run_file}.tmp"
mkdir -p "$scope_root"
printf '%s' "$run_id" > "$tmp_run_file"
mv "$tmp_run_file" "$current_run_file"

printf '%s\n' "$out_json"
