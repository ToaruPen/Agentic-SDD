#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

# This test suite must be robust even when invoked from `scripts/review-cycle.sh`,
# which sets TEST_COMMAND in the environment.
unset TEST_COMMAND || true

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
schema_src="${repo_root}/.agent/schemas/review.json"
review_cycle_sh="${repo_root}/scripts/review-cycle.sh"
assemble_sot_py="${repo_root}/scripts/assemble-sot.py"
validator_py="${repo_root}/scripts/validate-review-json.py"

if [[ ! -f "$schema_src" ]]; then
  eprint "Missing schema: $schema_src"
  exit 1
fi

if [[ ! -x "$review_cycle_sh" ]]; then
  eprint "Missing script or not executable: $review_cycle_sh"
  exit 1
fi

if [[ ! -x "$assemble_sot_py" ]]; then
  eprint "Missing assemble-sot or not executable: $assemble_sot_py"
  exit 1
fi

if [[ ! -x "$validator_py" ]]; then
  eprint "Missing validator or not executable: $validator_py"
  exit 1
fi

python3 -c 'import json,sys; json.load(open(sys.argv[1],"r",encoding="utf-8"))' "$schema_src" >/dev/null

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-review-cycle)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q
mkdir -p "$tmpdir/.agent/schemas"
cp -p "$schema_src" "$tmpdir/.agent/schemas/review.json"

cat > "$tmpdir/hello.txt" <<'EOF'
hello
EOF

git -C "$tmpdir" add hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q

# PRD/Epic fixtures
mkdir -p "$tmpdir/docs/prd" "$tmpdir/docs/epics"

cat > "$tmpdir/docs/prd/prd.md" <<'EOF'
# PRD: Test

## Meta

meta

## 1. Purpose

purpose

## 5. Out of scope

out

## 8. Glossary

terms

## Completion checklist

should not appear
EOF

cat > "$tmpdir/docs/epics/epic.md" <<'EOF'
# Epic: Test

## Meta

meta

## 1. Overview

overview

## 4. Issue plan

issues

## 8. Unknown

unknown

## Change log

should not appear
EOF

git -C "$tmpdir" add docs/prd/prd.md docs/epics/epic.md
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "add docs" -q

# DIFF_MODE=pr smoke test (whole branch diff)
# Ensure the base branch is called "master" (git init default may be "main").
git -C "$tmpdir" branch -M master
git -C "$tmpdir" checkout -b feature -q
echo "feature-change" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "feature" -q

(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=pr \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>/dev/null

# Staged diff only (should succeed)
echo "change1" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt

(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=auto \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>/dev/null

# TESTS without TEST_COMMAND must be explicit "not run: <reason>" (should fail)
set +e
(cd "$tmpdir" && SOT="test" TESTS="ran: fake" DIFF_MODE=staged \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>"$tmpdir/stderr_notrun"
code=$?
set -e
if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when TEST_COMMAND is missing and TESTS is not 'not run: ...'"
  exit 1
fi
if ! grep -q "Set TEST_COMMAND to actually run tests" "$tmpdir/stderr_notrun"; then
  eprint "Expected TEST_COMMAND enforcement error, got:"
  cat "$tmpdir/stderr_notrun" >&2
  exit 1
fi

# Both staged and worktree diffs non-empty (should fail)
echo "change2" >> "$tmpdir/hello.txt"

set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=auto \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>"$tmpdir/stderr"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when both staged and worktree diffs exist"
  exit 1
fi

if ! grep -q "Both staged and worktree diffs are non-empty" "$tmpdir/stderr"; then
  eprint "Expected ambiguity error message, got:"
  cat "$tmpdir/stderr" >&2
  exit 1
fi

# Full run (no real codex; use stub)
cat > "$tmpdir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != "exec" ]]; then
  echo "unsupported" >&2
  exit 2
fi
	shift
	
	out=""
	configs=()
	while [[ $# -gt 0 ]]; do
	  case "$1" in
	    -c)
	      configs+=("$2")
	      shift 2
	      ;;
	    --output-last-message)
	      out="$2"
	      shift 2
	      ;;
	    -)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

		cat >/dev/null || true
		
		expected="${EXPECTED_EFFORT:-low}"
			if ! printf '%s\n' "${configs[@]}" | grep -qxF "model_reasoning_effort=\"${expected}\""; then
			  echo "missing -c model_reasoning_effort=\"${expected}\" (configs: ${configs[*]})" >&2
			  exit 2
			fi
	
	if [[ -z "$out" ]]; then
	  echo "missing --output-last-message" >&2
	  exit 2
	fi

mkdir -p "$(dirname "$out")"
cat > "$out" <<'JSON'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "stub"
}
JSON
EOF
chmod +x "$tmpdir/codex"

cat > "$tmpdir/issue-body.md" <<'EOF'
## Background

- Epic: docs/epics/epic.md
- PRD: docs/prd/prd.md

## Acceptance Criteria

- [ ] AC1: something
EOF

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low EXPECTED_EFFORT=low \
  "$review_cycle_sh" issue-1 run1) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json" ]]; then
  eprint "Expected review.json to be created"
  exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=none EXPECTED_EFFORT=minimal \
  "$review_cycle_sh" issue-1 run_effort_none) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run_effort_none/review.json" ]]; then
  eprint "Expected review.json to be created for REASONING_EFFORT=none"
  exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=minimal EXPECTED_EFFORT=minimal \
  "$review_cycle_sh" issue-1 run_effort_minimal) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run_effort_minimal/review.json" ]]; then
  eprint "Expected review.json to be created for REASONING_EFFORT=minimal"
  exit 1
fi

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/sot.txt" ]]; then
  eprint "Expected sot.txt to be created"
  exit 1
fi

if ! grep -q "== PRD (wide excerpt) ==" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/sot.txt"; then
  eprint "Expected PRD excerpt in sot.txt"
  exit 1
fi

if grep -q "Completion checklist" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/sot.txt"; then
  eprint "Did not expect excluded PRD section in sot.txt"
  exit 1
fi

if grep -q "Change log" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/sot.txt"; then
  eprint "Did not expect excluded Epic section in sot.txt"
  exit 1
fi

# Truncation should keep tail (manual SoT tends to be appended at the end)
long_sot="$(python3 - <<'PY'
print("A" * 6000 + "\nTAIL_SENTINEL\n")
PY
)"

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" SOT_MAX_CHARS=3000 SOT="$long_sot" \
  TESTS="not run: reason" DIFF_MODE=staged CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run3) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run3/sot.txt" ]]; then
  eprint "Expected sot.txt to be created for truncation test"
  exit 1
fi

if ! grep -q "\\[TRUNCATED\\]" "$tmpdir/.agentic-sdd/reviews/issue-1/run3/sot.txt"; then
  eprint "Expected [TRUNCATED] marker in sot.txt"
  exit 1
fi

if ! grep -q "TAIL_SENTINEL" "$tmpdir/.agentic-sdd/reviews/issue-1/run3/sot.txt"; then
  eprint "Expected tail sentinel to be preserved in sot.txt"
  exit 1
fi

size=$(wc -c < "$tmpdir/.agentic-sdd/reviews/issue-1/run3/sot.txt" | tr -d ' ')
if [[ "$size" -gt 3000 ]]; then
  eprint "Expected sot.txt size <= 3000, got: $size"
  exit 1
fi

# Fail-fast when referenced PRD is missing
cat > "$tmpdir/issue-missing.md" <<'EOF'
## Background

- Epic: docs/epics/epic.md
- PRD: docs/prd/missing.md
EOF

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-missing.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run2) >/dev/null 2>"$tmpdir/stderr2"
code2=$?
set -e

if [[ "$code2" -eq 0 ]]; then
  eprint "Expected failure when referenced PRD is missing"
  exit 1
fi

if ! grep -q "PRD file not found" "$tmpdir/stderr2"; then
  eprint "Expected missing PRD error, got:"
  cat "$tmpdir/stderr2" >&2
  exit 1
fi

# Validator smoke test
cat > "$tmpdir/review.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "No issues."
}
EOF

python3 "$validator_py" "$tmpdir/review.json" --scope-id issue-1 >/dev/null

# Validator: --format should not escape non-ASCII (keep UTF-8)
cat > "$tmpdir/review-ja.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "日本語テスト"
}
EOF

python3 "$validator_py" "$tmpdir/review-ja.json" --scope-id issue-1 --format >/dev/null

if grep -q "\\\\u" "$tmpdir/review-ja.json"; then
  eprint "Did not expect Unicode escaping in formatted JSON"
  cat "$tmpdir/review-ja.json" >&2
  exit 1
fi

if ! grep -q "日本語テスト" "$tmpdir/review-ja.json"; then
  eprint "Expected UTF-8 Japanese text to remain in formatted JSON"
  cat "$tmpdir/review-ja.json" >&2
  exit 1
fi

# Validator: Blocked requires at least one P0/P1
cat > "$tmpdir/review-blocked.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-2",
  "status": "Blocked",
  "findings": [
    {
      "title": "Must fix",
      "body": "blocking",
      "priority": "P0",
      "code_location": {
        "repo_relative_path": "hello.txt",
        "line_range": {"start": 1, "end": 1}
      }
    }
  ],
  "questions": [],
  "overall_explanation": "Blocking issue."
}
EOF

python3 "$validator_py" "$tmpdir/review-blocked.json" --scope-id issue-2 >/dev/null

# Validator: numeric priority should fail
cat > "$tmpdir/review-bad-priority.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-3",
  "status": "Blocked",
  "findings": [
    {
      "title": "Bad priority type",
      "body": "blocking",
      "priority": 0,
      "code_location": {
        "repo_relative_path": "hello.txt",
        "line_range": {"start": 1, "end": 1}
      }
    }
  ],
  "questions": [],
  "overall_explanation": "Blocking issue."
}
EOF

set +e
python3 "$validator_py" "$tmpdir/review-bad-priority.json" --scope-id issue-3 >/dev/null 2>"$tmpdir/stderr3"
code3=$?
set -e

if [[ "$code3" -eq 0 ]]; then
  eprint "Expected failure for numeric priority"
  exit 1
fi

# Claude engine test (use stub with wrapped format like real Claude CLI)
cat > "$tmpdir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

tools=""
allowed_tools=""
add_dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      shift
      ;;
    --model|--output-format|--betas)
      shift 2 2>/dev/null || shift
      ;;
    --json-schema)
      shift 2 2>/dev/null || shift
      ;;
    --tools)
      tools="${2:-}"
      shift 2 2>/dev/null || shift
      ;;
    --allowedTools|--allowed-tools)
      allowed_tools="${2:-}"
      shift 2 2>/dev/null || shift
      ;;
    --add-dir)
      add_dirs+=("${2:-}")
      shift 2 2>/dev/null || shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$tools" != "Read" ]]; then
  echo "expected --tools Read, got: '$tools'" >&2
  exit 2
fi

if [[ "$allowed_tools" != "Read" ]]; then
  echo "expected --allowedTools Read, got: '$allowed_tools'" >&2
  exit 2
fi

if [[ "${#add_dirs[@]}" -eq 0 ]]; then
  echo "missing --add-dir" >&2
  exit 2
fi

if [[ -n "${EXPECTED_CLAUDE_ADD_DIR:-}" ]]; then
  found=0
  for d in "${add_dirs[@]}"; do
    if [[ "$d" == "$EXPECTED_CLAUDE_ADD_DIR" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "expected --add-dir to include: '$EXPECTED_CLAUDE_ADD_DIR' (got: ${add_dirs[*]})" >&2
    exit 2
  fi
fi

# Read stdin and discard
cat >/dev/null || true

# Output wrapped JSON format (like real Claude CLI with --output-format json)
cat <<'JSON'
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 1234,
  "num_turns": 1,
  "session_id": "test-session",
  "total_cost_usd": 0.001,
  "structured_output": {
    "schema_version": 3,
    "scope_id": "issue-claude",
    "status": "Approved",
    "findings": [],
    "questions": [],
    "overall_explanation": "claude stub wrapped"
  }
}
JSON
EOF
chmod +x "$tmpdir/claude"

# Reset diff state for Claude test
git -C "$tmpdir" reset HEAD~1 --soft 2>/dev/null || true
echo "claude-change" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt

expected_claude_add_dir="$(cd "$tmpdir" && pwd -P)"
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  REVIEW_ENGINE=claude CLAUDE_BIN="$tmpdir/claude" CLAUDE_MODEL=stub \
  EXPECTED_CLAUDE_ADD_DIR="$expected_claude_add_dir" \
  "$review_cycle_sh" issue-claude run1) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/review.json" ]]; then
  eprint "Expected review.json to be created for Claude engine"
  exit 1
fi

if ! grep -q "claude stub wrapped" "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/review.json"; then
  eprint "Expected Claude stub wrapped output in review.json"
  exit 1
fi

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/prompt.txt" ]]; then
  eprint "Expected prompt.txt to be created for Claude engine"
  exit 1
fi

# Claude should receive the diff as a local file path (not embedded content).
if ! grep -q "^Diff-File: \\.agentic-sdd/reviews/issue-claude/run1/diff\\.patch$" "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/prompt.txt"; then
  eprint "Expected Diff-File path in Claude prompt"
  exit 1
fi

if grep -q "^Diff:$" "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/prompt.txt"; then
  eprint "Did not expect embedded diff marker (Diff:) in Claude prompt"
  exit 1
fi

if grep -q "^diff --git " "$tmpdir/.agentic-sdd/reviews/issue-claude/run1/prompt.txt"; then
  eprint "Did not expect embedded diff content in Claude prompt"
  exit 1
fi

# Invalid REVIEW_ENGINE should fail
set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=staged \
  REVIEW_ENGINE=invalid \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>"$tmpdir/stderr4"
code4=$?
set -e

if [[ "$code4" -eq 0 ]]; then
  eprint "Expected failure for invalid REVIEW_ENGINE"
  exit 1
fi

if ! grep -q "Invalid REVIEW_ENGINE" "$tmpdir/stderr4"; then
  eprint "Expected invalid engine error, got:"
  cat "$tmpdir/stderr4" >&2
  exit 1
fi

# Claude error response should fail gracefully
cat > "$tmpdir/claude-error" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null || true
cat <<'JSON'
{
  "type": "result",
  "subtype": "error_max_turns",
  "is_error": false,
  "errors": ["Max turns exceeded"]
}
JSON
EOF
chmod +x "$tmpdir/claude-error"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  REVIEW_ENGINE=claude CLAUDE_BIN="$tmpdir/claude-error" CLAUDE_MODEL=stub \
  "$review_cycle_sh" issue-claude-err run1) >/dev/null 2>"$tmpdir/stderr5"
code5=$?
set -e

if [[ "$code5" -eq 0 ]]; then
  eprint "Expected failure for Claude error response"
  exit 1
fi

if ! grep -q "error_max_turns" "$tmpdir/stderr5"; then
  eprint "Expected error_max_turns in stderr, got:"
  cat "$tmpdir/stderr5" >&2
  exit 1
fi

eprint "OK: scripts/tests/test-review-cycle.sh"
