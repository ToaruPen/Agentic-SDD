#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review-cycle.sh <scope-id> [run-id] [--dry-run]

Generate a review JSON (schema v3) via `codex exec --output-schema`.

Positional arguments:
  scope-id   Identifier for the reviewed scope (e.g. issue-123)
  run-id     Optional run identifier (default: reuse .current_run, else timestamp)

Options:
  --dry-run  Print the plan and exit without calling codex
  -h, --help Show help

Required environment:
  One of:
    SOT                  Manual source-of-truth (paths / links / summary)
    GH_ISSUE             GitHub issue number or URL (uses `gh issue view`)
    GH_ISSUE_BODY_FILE   Local file containing issue body (test/offline)
    SOT_FILES            Extra SoT files (repo-relative paths, space-separated)

  And:
    TESTS                Short test summary (can be 'not run: reason')
                        OR set TEST_COMMAND to run tests and auto-populate TESTS.

Optional environment:
  GH_ISSUE             GitHub issue number or URL
  GH_REPO              Repo for gh (OWNER/REPO)
  GH_INCLUDE_COMMENTS  1 to include comments in issue JSON (default: 0)
  GH_ISSUE_BODY_FILE   Local file containing issue body (test/offline)
  SOT_FILES            Extra SoT files (repo-relative paths, space-separated)
  SOT_MAX_CHARS        Max chars for assembled SoT bundle (0 = no limit)
  TEST_COMMAND     Command to run tests (captures full output to tests.txt)
  DIFF_MODE        staged|worktree|auto (default: auto)
  DIFF_FILE        Optional path to a diff file (overrides DIFF_MODE)
  OUTPUT_ROOT      Output root (default: <repo_root>/.agentic-sdd/reviews)
  SCHEMA_PATH      JSON schema path (default: <repo_root>/.agent/schemas/review.json)
  CONSTRAINTS      Additional constraints string (default: none)

  Engine selection:
  REVIEW_ENGINE    codex|claude (default: codex)

  Codex options (when REVIEW_ENGINE=codex):
  CODEX_BIN        codex binary (default: codex)
  MODEL            codex model (default: gpt-5.2-codex)
  REASONING_EFFORT high|medium|low (default: high)

  Claude options (when REVIEW_ENGINE=claude):
  CLAUDE_BIN       claude binary (default: claude)
  CLAUDE_MODEL     claude model (default: claude-opus-4-5-20250929)
                   Note: Claude Opus 4.5 has 200K token context window (half of Codex's 400K).
                   For large PRD+Epic+diff combinations, consider setting SOT_MAX_CHARS.

  Common options:
  EXEC_TIMEOUT_SEC Optional timeout (uses timeout/gtimeout if available)
  FORMAT_JSON      1 to pretty-format output JSON (default: 1)

Notes:
  - This script writes outputs under .agentic-sdd/ (recommended to gitignore).
  - In DIFF_MODE=auto, if both staged and worktree diffs are non-empty, this script
    fails and asks you to choose.
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
diff_mode="${DIFF_MODE:-auto}"
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
model="${MODEL:-gpt-5.2-codex}"
effort="${REASONING_EFFORT:-high}"

# Claude options
claude_bin="${CLAUDE_BIN:-claude}"
claude_model="${CLAUDE_MODEL:-claude-opus-4-5-20250929}"

# Common options
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"
format_json="${FORMAT_JSON:-1}"

sot="${SOT:-}"
tests_summary="${TESTS:-}"
test_command="${TEST_COMMAND:-}"

gh_issue="${GH_ISSUE:-}"
gh_repo="${GH_REPO:-}"
gh_include_comments="${GH_INCLUDE_COMMENTS:-0}"
gh_issue_body_file="${GH_ISSUE_BODY_FILE:-}"
sot_files_raw="${SOT_FILES:-}"
sot_max_chars="${SOT_MAX_CHARS:-0}"

declare -a sot_files=()
if [[ -n "$sot_files_raw" ]]; then
  # shellcheck disable=SC2206
  sot_files=($sot_files_raw)
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
out_diff="${run_dir}/diff.patch"
out_tests="${run_dir}/tests.txt"

out_sot="${run_dir}/sot.txt"
out_issue_json="${run_dir}/issue.json"
out_issue_body="${run_dir}/issue.txt"

diff_source=""

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

write_tests() {
  local exit_code=0

  if [[ -n "$test_command" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      if [[ -z "$tests_summary" ]]; then
        tests_summary="command: ${test_command} (not run: --dry-run)"
      fi
      return 0
    fi

    ensure_run_dir
    {
      printf 'Command: %s\n' "$test_command"
      printf 'Started: %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
      printf '\n'
    } > "$out_tests"

    set +e
    bash -lc "$test_command" >> "$out_tests" 2>&1
    exit_code=$?
    set -e

    {
      printf '\n'
      printf 'Exit: %s\n' "$exit_code"
      printf 'Finished: %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
    } >> "$out_tests"

    if [[ -z "$tests_summary" ]]; then
      if [[ "$exit_code" -eq 0 ]]; then
        tests_summary="command: ${test_command} (exit=0)"
      else
        tests_summary="command: ${test_command} (exit=${exit_code})"
      fi
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
      eprint "Invalid DIFF_MODE: $diff_mode (use staged|worktree|auto)"
      exit 2
      ;;
  esac

  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ ! -s "$out_diff" ]]; then
      eprint "Diff is empty after collection: $out_diff"
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
  eprint "- out_diff: $out_diff"
  eprint "- out_tests: $out_tests"
  eprint "- out_sot: $out_sot"
  eprint "- diff_mode: $diff_mode"
  if [[ -n "$diff_source" ]]; then
    eprint "- diff_source: $diff_source"
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

if [[ ! -f "$schema_path" ]]; then
  eprint "Schema not found: $schema_path"
  eprint "Expected this repo to have .agent/schemas/review.json installed."
  exit 1
fi

# Validate engine selection and check binary availability
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

if ! command -v python3 >/dev/null 2>&1; then
  eprint "python3 not found (required for validation)."
  exit 1
fi

tmp_json="${out_json}.tmp.$$"
tmp_prompt="${run_dir}/prompt.txt"

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
  printf 'Constraints: %s\n' "$constraints"
  printf 'Diff:\n'
  cat "$out_diff"
} > "$tmp_prompt"

# Execute review engine
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
    # Claude CLI --json-schema expects JSON string, not file path.
    # Read the schema file content and remove $schema meta field if present
    # (Claude CLI doesn't handle JSON Schema meta fields correctly).
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

    # Claude CLI outputs wrapped JSON with structured_output field.
    # Extract the structured_output and check for errors.
    tmp_claude_out="${tmp_json}.claude.$$"
    "${cmd[@]}" < "$tmp_prompt" > "$tmp_claude_out"

    # Extract structured_output from Claude's wrapped response.
    # Claude CLI with --output-format json wraps the schema output in:
    # {"type":"result", "structured_output": {...}, ...}
    # If structured_output is missing, assume the output is already unwrapped.
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

# Check for Claude CLI wrapper format (has 'type' and 'subtype' fields)
is_wrapped = 'type' in data and data.get('type') == 'result'

if is_wrapped:
    # Check for errors
    subtype = data.get('subtype', '')
    if subtype and subtype != 'success':
        errors = data.get('errors', [])
        print(f'Claude returned error: {subtype}', file=sys.stderr)
        if errors:
            for err in errors:
                print(f'  {err}', file=sys.stderr)
        sys.exit(1)

    # Extract structured_output
    structured = data.get('structured_output')
    if structured is None:
        print('Claude output missing structured_output field', file=sys.stderr)
        print('Full response:', file=sys.stderr)
        print(json.dumps(data, indent=2), file=sys.stderr)
        sys.exit(1)
    output = structured
else:
    # Not wrapped - use as-is (e.g., test stub output)
    output = data

# Write extracted JSON
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

if [[ ! -f "$tmp_json" || ! -s "$tmp_json" ]]; then
  eprint "$review_engine did not produce output: $tmp_json"
  exit 1
fi

mv "$tmp_json" "$out_json"

validate_args=("$out_json" --scope-id "$scope_id")
if [[ "$format_json" != "0" ]]; then
  validate_args+=(--format)
fi
python3 "$script_dir/validate-review-json.py" "${validate_args[@]}"

tmp_run_file="${current_run_file}.tmp"
mkdir -p "$scope_root"
printf '%s' "$run_id" > "$tmp_run_file"
mv "$tmp_run_file" "$current_run_file"

printf '%s\n' "$out_json"
