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
git -C "$tmpdir" branch -M main

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

# Default diff mode (range) should compare BASE_REF...HEAD.
# In this test repo, origin/main does not exist, so it must fallback to main.
git -C "$tmpdir" switch -c feature/default-range -q
echo "range-change" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "range change" -q

(cd "$tmpdir" && SOT="test" TESTS="not run: reason" \
  "$review_cycle_sh" issue-range --dry-run) >/dev/null 2>"$tmpdir/stderr_range_ok"
if ! grep -q "diff_source: range" "$tmpdir/stderr_range_ok"; then
  eprint "Expected default diff source to be range"
  cat "$tmpdir/stderr_range_ok" >&2
  exit 1
fi
if ! grep -q "diff_detail: main" "$tmpdir/stderr_range_ok"; then
  eprint "Expected range diff base fallback to main"
  cat "$tmpdir/stderr_range_ok" >&2
  exit 1
fi

# Default range mode should fail-fast when BASE_REF...HEAD has no diff.
git -C "$tmpdir" switch main -q
set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" \
  "$review_cycle_sh" issue-range-empty --dry-run) >/dev/null 2>"$tmpdir/stderr_range_empty"
code_range_empty=$?
set -e
if [[ "$code_range_empty" -eq 0 ]]; then
  eprint "Expected failure when range diff is empty"
  exit 1
fi
if ! grep -q "Diff is empty (range: main...HEAD)." "$tmpdir/stderr_range_empty"; then
  eprint "Expected empty range diff error message, got:"
  cat "$tmpdir/stderr_range_empty" >&2
  exit 1
fi
git -C "$tmpdir" switch feature/default-range -q

# If fetch for origin/main fails and the ref is missing, range mode should
# still fallback to local main (preserve legacy behavior).
origin_range_bare="$tmpdir/origin-range.git"
git init -q --bare "$origin_range_bare"
git -C "$tmpdir" remote add origin "$origin_range_bare"
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" \
  "$review_cycle_sh" issue-range-missing --dry-run) >/dev/null 2>"$tmpdir/stderr_range_missing"
if ! grep -q "diff_detail: main" "$tmpdir/stderr_range_missing"; then
  eprint "Expected fallback to main when remote-tracking base cannot be fetched"
  cat "$tmpdir/stderr_range_missing" >&2
  exit 1
fi

# Range mode should fetch remote-tracking base refs before diffing.
git -C "$tmpdir" checkout main -q
git -C "$tmpdir" push -u origin main -q
old_origin_main="$(git -C "$tmpdir" rev-parse origin/main)"

updater="$tmpdir/updater"
git clone -q "$origin_range_bare" "$updater"
git -C "$updater" checkout main -q
echo "remote-main-update" >> "$updater/hello.txt"
git -C "$updater" add hello.txt
git -C "$updater" -c user.name=test -c user.email=test@example.com commit -m "main update" -q
git -C "$updater" push origin main -q
new_origin_main="$(git -C "$updater" rev-parse HEAD)"

# Force local origin/main to stale SHA; /review-cycle should fetch and refresh it.
git -C "$tmpdir" update-ref refs/remotes/origin/main "$old_origin_main"
git -C "$tmpdir" switch feature/default-range -q
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" \
  "$review_cycle_sh" issue-range-fetch --dry-run) >/dev/null 2>"$tmpdir/stderr_range_fetch"
current_origin_main="$(git -C "$tmpdir" rev-parse origin/main)"
if [[ "$current_origin_main" != "$new_origin_main" ]]; then
  eprint "Expected /review-cycle to fetch and refresh origin/main"
  eprint "current=$current_origin_main expected=$new_origin_main"
  cat "$tmpdir/stderr_range_fetch" >&2
  exit 1
fi

# Range mode should prefer local BASE_REF values containing "/" even when a
# same-prefix remote exists.
git -C "$tmpdir" switch main -q
git -C "$tmpdir" branch release/v1
git -C "$tmpdir" switch -c feature/local-slash-base -q
echo "local-slash-base-change" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "local slash base change" -q
release_shadow_bare="$tmpdir/release-shadow.git"
git init -q --bare "$release_shadow_bare"
git -C "$tmpdir" remote add release "$release_shadow_bare"
git -C "$tmpdir" update-ref refs/remotes/release/v1 "$(git -C "$tmpdir" rev-parse release/v1)"
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" BASE_REF=release/v1 \
  "$review_cycle_sh" issue-range-local-slash --dry-run) >/dev/null 2>"$tmpdir/stderr_range_local_slash"
if ! grep -q "diff_detail: release/v1" "$tmpdir/stderr_range_local_slash"; then
  eprint "Expected local slash base ref to be used without remote fetch failure"
  cat "$tmpdir/stderr_range_local_slash" >&2
  exit 1
fi

# Range mode should fail-fast when uncommitted local changes exist.
echo "range-local-change" >> "$tmpdir/hello.txt"
set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" \
  "$review_cycle_sh" issue-range-dirty --dry-run) >/dev/null 2>"$tmpdir/stderr_range_dirty"
code_range_dirty=$?
set -e
if [[ "$code_range_dirty" -eq 0 ]]; then
  eprint "Expected failure when DIFF_MODE=range has local changes"
  exit 1
fi
if ! grep -q "DIFF_MODE=range requires a clean working tree" "$tmpdir/stderr_range_dirty"; then
  eprint "Expected clean working tree error message, got:"
  cat "$tmpdir/stderr_range_dirty" >&2
  exit 1
fi
git -C "$tmpdir" restore hello.txt

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
model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      out="$2"
      shift 2
      ;;
    -m|--model)
      model="${2:-}"
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

if [[ -n "${CODEX_STUB_MOVE_MAIN_TO:-}" ]]; then
  git branch -f main "$CODEX_STUB_MOVE_MAIN_TO" >/dev/null
fi

if [[ -z "$out" ]]; then
  echo "missing --output-last-message" >&2
  exit 2
fi

mkdir -p "$(dirname "$out")"
# Generate JSON without requiring python3 in this stub.
json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

escaped_model="$(json_escape "$model")"
cat > "$out" <<JSON
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "stub (model=${escaped_model})"
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

# Base SHA in review metadata must be pinned to the diff-collection time.
range_repo="$tmpdir/range-meta-pin"
mkdir -p "$range_repo/.agent/schemas"
cp -p "$schema_src" "$range_repo/.agent/schemas/review.json"
git -C "$range_repo" init -q
cat > "$range_repo/hello.txt" <<'EOF'
hello
EOF
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$range_repo" branch -M main
git -C "$range_repo" switch -c feature/range-base-pin -q
echo "feature-change" >> "$range_repo/hello.txt"
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "feature change" -q
base_sha_before="$(git -C "$range_repo" rev-parse main)"
git -C "$range_repo" switch -c main-future main -q
echo "main-future" >> "$range_repo/hello.txt"
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "main future" -q
base_sha_after="$(git -C "$range_repo" rev-parse HEAD)"
git -C "$range_repo" switch feature/range-base-pin -q

(cd "$range_repo" && SOT="test" TESTS="not run: reason" DIFF_MODE=range BASE_REF=main \
  CODEX_STUB_MOVE_MAIN_TO="$base_sha_after" CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run-range-base-pin) >/dev/null

metadata_base_sha="$(python3 - "$range_repo/.agentic-sdd/reviews/issue-1/run-range-base-pin/review-metadata.json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("base_sha", ""))
PY
)"
if [[ "$metadata_base_sha" != "$base_sha_before" ]]; then
  eprint "Expected review metadata base_sha to be pinned at diff collection time"
  eprint "metadata=$metadata_base_sha expected=$base_sha_before"
  exit 1
fi
if [[ "$metadata_base_sha" == "$base_sha_after" ]]; then
  eprint "Expected review metadata base_sha not to drift to post-diff base"
  eprint "unexpected=$metadata_base_sha"
  exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run1) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json" ]]; then
  eprint "Expected review.json to be created"
  exit 1
fi

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" ]]; then
  eprint "Expected review-metadata.json to be created"
  exit 1
fi

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/sot.txt" ]]; then
  eprint "Expected sot.txt to be created"
  exit 1
fi

if ! grep -q "model=stub" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json"; then
  eprint "Expected model passthrough to codex stub (MODEL=stub)"
  cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json" >&2
  exit 1
fi

if ! grep -q '"diff_source": "staged"' "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
  eprint "Expected diff_source=staged in review metadata"
  cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
  exit 1
fi

if ! grep -q '"head_sha": "' "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
  eprint "Expected head_sha in review metadata"
  cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
  exit 1
fi

# CLI --model should override env MODEL
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=envstub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run-model-cli --model clistub) >/dev/null
if ! grep -q "model=clistub" "$tmpdir/.agentic-sdd/reviews/issue-1/run-model-cli/review.json"; then
  eprint "Expected --model to override env MODEL"
  cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-model-cli/review.json" >&2
  exit 1
fi

# Env MODEL should still work when no --model is provided
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  CODEX_BIN="$tmpdir/codex" MODEL=envonly REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run-model-env) >/dev/null
if ! grep -q "model=envonly" "$tmpdir/.agentic-sdd/reviews/issue-1/run-model-env/review.json"; then
  eprint "Expected env MODEL to be used when --model is not provided"
  cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-model-env/review.json" >&2
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

# TEST_COMMAND stderr detection (warn should succeed, fail should stop before engine)
set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" DIFF_MODE=staged \
  TEST_COMMAND='bash -lc "echo boom >&2; exit 0"' TESTS="" \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run-stderr-warn) >/dev/null 2>"$tmpdir/stderr-stderr-warn"
code_stderr_warn=$?
set -e
if [[ "$code_stderr_warn" -ne 0 ]]; then
  eprint "Expected success for stderr warn policy, got exit=$code_stderr_warn"
  cat "$tmpdir/stderr-stderr-warn" >&2
  exit 1
fi
if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-warn/tests.stderr" ]]; then
  eprint "Expected tests.stderr to be created"
  exit 1
fi
if ! grep -q "WARNING: test command produced stderr output" "$tmpdir/stderr-stderr-warn"; then
  eprint "Expected stderr warning message, got:"
  cat "$tmpdir/stderr-stderr-warn" >&2
  exit 1
fi
if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-warn/review.json" ]]; then
  eprint "Expected review.json to be created for warn policy"
  exit 1
fi
if ! grep -q "Tests-Stderr:" "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-warn/prompt.txt"; then
  eprint "Expected Tests-Stderr to appear in prompt.txt"
  exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" DIFF_MODE=staged \
  TEST_COMMAND='bash -lc "echo boom >&2; exit 0"' TESTS="" TEST_STDERR_POLICY=fail \
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run-stderr-fail) >/dev/null 2>"$tmpdir/stderr-stderr-fail"
code_stderr_fail=$?
set -e
if [[ "$code_stderr_fail" -eq 0 ]]; then
  eprint "Expected failure for stderr fail policy"
  exit 1
fi
if ! grep -q "TEST_STDERR_POLICY=fail" "$tmpdir/stderr-stderr-fail"; then
  eprint "Expected fail policy error message, got:"
  cat "$tmpdir/stderr-stderr-fail" >&2
  exit 1
fi
if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-fail/tests.stderr" ]]; then
  eprint "Expected tests.stderr to be created for fail policy"
  exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-fail/review.json" ]]; then
  eprint "Did not expect review.json to be created when failing on stderr"
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

# Parse arguments to find --json-schema
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
    *)
      shift
      ;;
  esac
done

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

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
  REVIEW_ENGINE=claude CLAUDE_BIN="$tmpdir/claude" CLAUDE_MODEL=stub \
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
