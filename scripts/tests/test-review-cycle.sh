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

cat >"$tmpdir/hello.txt" <<'EOF'
hello
EOF

git -C "$tmpdir" add hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir" branch -M main

# PRD/Epic fixtures
mkdir -p "$tmpdir/docs/prd" "$tmpdir/docs/epics"

cat >"$tmpdir/docs/prd/prd.md" <<'EOF'
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

cat >"$tmpdir/docs/epics/epic.md" <<'EOF'
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
echo "range-change" >>"$tmpdir/hello.txt"
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
echo "remote-main-update" >>"$updater/hello.txt"
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
echo "local-slash-base-change" >>"$tmpdir/hello.txt"
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

# SOT_FILES parser should support shell-escaped spaces in paths (without splitting).
mkdir -p "$tmpdir/docs/sot files"
cat >"$tmpdir/docs/sot files/extra.md" <<'EOF'
This is an extra SoT file with a space in the path.
EOF

if ! (cd "$tmpdir" && SOT_FILES='docs/sot\ files/extra.md' TESTS="not run: reason" \
	DIFF_MODE=range "$review_cycle_sh" issue-sotfiles --dry-run) >/dev/null 2>"$tmpdir/stderr-sotfiles-escaped"; then
	eprint "Expected shell-escaped SOT_FILES path to be parsed"
	cat "$tmpdir/stderr-sotfiles-escaped" >&2
	exit 1
fi
if ! grep -q "sot_files: docs/sot files/extra.md" "$tmpdir/stderr-sotfiles-escaped"; then
	eprint "Expected escaped path to be reported in plan"
	cat "$tmpdir/stderr-sotfiles-escaped" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && SOT_FILES='"docs/sot files/extra.md' TESTS="not run: reason" \
	DIFF_MODE=range "$review_cycle_sh" issue-sotfiles-bad-quote --dry-run) >/dev/null 2>"$tmpdir/stderr-sotfiles-bad-quote"
code_sotfiles_bad_quote=$?
set -e
if [[ "$code_sotfiles_bad_quote" -eq 0 ]]; then
	eprint "Expected unterminated quote in SOT_FILES to fail"
	cat "$tmpdir/stderr-sotfiles-bad-quote" >&2
	exit 1
fi
if ! grep -q "Invalid SOT_FILES" "$tmpdir/stderr-sotfiles-bad-quote"; then
	eprint "Expected shell-like parse error for bad SOT_FILES quoting"
	cat "$tmpdir/stderr-sotfiles-bad-quote" >&2
	exit 1
fi

# Range mode should fail-fast when uncommitted local changes exist.
echo "range-local-change" >>"$tmpdir/hello.txt"
set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" REVIEW_CYCLE_INCREMENTAL=1 \
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
echo "change1" >>"$tmpdir/hello.txt"
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
echo "change2" >>"$tmpdir/hello.txt"

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

# Worktree diff mode should succeed even when staged changes also exist
if ! (cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=worktree \
	"$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>"$tmpdir/stderr_worktree"; then
	eprint "Expected DIFF_MODE=worktree to succeed when worktree has diff"
	cat "$tmpdir/stderr_worktree" >&2
	exit 1
fi
if ! grep -q "diff_source: worktree" "$tmpdir/stderr_worktree"; then
	eprint "Expected worktree diff source for DIFF_MODE=worktree"
	cat "$tmpdir/stderr_worktree" >&2
	exit 1
fi

# Full run (no real codex; use stub)
cat >"$tmpdir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi

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

cat >"$tmpdir/issue-body.md" <<'EOF'
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
cat >"$range_repo/hello.txt" <<'EOF'
hello
EOF
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$range_repo" branch -M main
git -C "$range_repo" switch -c feature/range-base-pin -q
echo "feature-change" >>"$range_repo/hello.txt"
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "feature change" -q
base_sha_before="$(git -C "$range_repo" rev-parse main)"
git -C "$range_repo" switch -c main-future main -q
echo "main-future" >>"$range_repo/hello.txt"
git -C "$range_repo" add hello.txt
git -C "$range_repo" -c user.name=test -c user.email=test@example.com commit -m "main future" -q
base_sha_after="$(git -C "$range_repo" rev-parse HEAD)"
git -C "$range_repo" switch feature/range-base-pin -q

(cd "$range_repo" && SOT="test" TESTS="not run: reason" DIFF_MODE=range BASE_REF=main \
	CODEX_STUB_MOVE_MAIN_TO="$base_sha_after" CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-range-base-pin) >/dev/null

metadata_base_sha="$(
	python3 - "$range_repo/.agentic-sdd/reviews/issue-1/run-range-base-pin/review-metadata.json" <<'PY'
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

if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/advisory.txt" ]]; then
	eprint "Did not expect advisory.txt when advisory lane is disabled by default"
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

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=worktree \
	CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-worktree) >/dev/null

if ! grep -q '"diff_source": "worktree"' "$tmpdir/.agentic-sdd/reviews/issue-1/run-worktree/review-metadata.json"; then
	eprint "Expected diff_source=worktree in review metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-worktree/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"head_sha": "' "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
	eprint "Expected head_sha in review metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
	exit 1
fi

for required_key in engine_fingerprint sot_fingerprint tests_fingerprint script_semantics_version; do
	if ! grep -q "\"${required_key}\":" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
		eprint "Expected ${required_key} in review metadata"
		cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
		exit 1
	fi
done

for required_key in prompt_bytes sot_bytes diff_bytes engine_runtime_ms reuse_reason non_reuse_reason; do
	if ! grep -q "\"${required_key}\":" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
		eprint "Expected ${required_key} in review metadata"
		cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
		exit 1
	fi
done

for required_key in engine_exit_code exec_timeout_sec timeout_applied timeout_bin engine_stderr_summary engine_stderr_sha256 engine_stderr_bytes; do
	if ! grep -q "\"${required_key}\":" "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
		eprint "Expected ${required_key} in review metadata"
		cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
		exit 1
	fi
done

engine_exit_code_run1="$(
	python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("engine_exit_code"))
PY
)"
if [[ "$engine_exit_code_run1" != "0" ]]; then
	eprint "Expected engine_exit_code=0 for successful run"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"non_reuse_reason": "no-previous-run"' "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
	eprint "Expected non_reuse_reason=no-previous-run on first run with default incremental mode"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"engine_version_available": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"; then
	eprint "Expected engine_version_available=true in review metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" >&2
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/advisory.txt" ]]; then
	eprint "Expected advisory.txt when advisory lane is enabled"
	exit 1
fi

if [[ ! -s "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/advisory.txt" ]]; then
	eprint "Expected advisory.txt to be non-empty"
	exit 1
fi

if ! grep -q '"advisory_lane_enabled": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/review-metadata.json"; then
	eprint "Expected advisory_lane_enabled=true in review metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/review-metadata.json" >&2
	exit 1
fi

advisory_prompt_file="$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/advisory-prompt.txt"
if [[ ! -f "$advisory_prompt_file" ]]; then
	eprint "Expected advisory-prompt.txt to be created when advisory lane is enabled"
	exit 1
fi
if ! grep -q "Tests-Stderr:" "$advisory_prompt_file"; then
	eprint "Expected advisory prompt to include Tests-Stderr"
	cat "$advisory_prompt_file" >&2
	exit 1
fi
if ! grep -q "Tests-Stderr-Policy:" "$advisory_prompt_file"; then
	eprint "Expected advisory prompt to include Tests-Stderr-Policy"
	cat "$advisory_prompt_file" >&2
	exit 1
fi

# Field ordering matters: advisory prompt must present context in the same
# sequence as the main review prompt (Tests → Stderr → Policy → Constraints)
# so the LLM receives a consistent information hierarchy across both lanes.
if ! python3 - "$advisory_prompt_file" <<'PY'; then
import sys

path = sys.argv[1]
lines = open(path, "r", encoding="utf-8").read().splitlines()
diff_idx = -1
for idx in range(len(lines) - 1, -1, -1):
    if lines[idx].strip().startswith("Diff:"):
        diff_idx = idx
        break

def find_last_header(prefix: str) -> int:
    if diff_idx < 0:
        return -1
    for idx in range(diff_idx - 1, -1, -1):
        if lines[idx].strip().startswith(prefix):
            return idx
    return -1

tests_idx = find_last_header("Tests:")
stderr_idx = find_last_header("Tests-Stderr:")
policy_idx = find_last_header("Tests-Stderr-Policy:")
constraints_idx = find_last_header("Constraints:")

if min(tests_idx, stderr_idx, policy_idx, constraints_idx) < 0:
    raise SystemExit(1)
if not (tests_idx < stderr_idx < policy_idx < constraints_idx):
    raise SystemExit(2)
PY
	eprint "Expected advisory prompt field ordering to match main prompt ordering"
	cat "$advisory_prompt_file" >&2
	exit 1
fi

cat >"$tmpdir/codex-advisory-fail-main-pass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi

if [[ ${1:-} != "exec" ]]; then
  exit 2
fi
shift

out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      out="$2"
      shift 2
      ;;
    -m|-c)
      shift 2
      ;;
    --sandbox)
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

if [[ -z "$out" ]]; then
  exit 2
fi

count_file="${CODEX_ADVISORY_COUNT_FILE:?}"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s' "$count" >"$count_file"

if [[ "$count" -eq 1 ]]; then
  echo "advisory simulated stderr" >&2
  exit 9
fi

mkdir -p "$(dirname "$out")"
cat >"$out" <<'JSON'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "advisory tolerated"
}
JSON
EOF
chmod +x "$tmpdir/codex-advisory-fail-main-pass"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_ADVISORY_COUNT_FILE="$tmpdir/advisory-count" \
	CODEX_BIN="$tmpdir/codex-advisory-fail-main-pass" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-tolerate) >/dev/null 2>"$tmpdir/stderr-advisory-tolerate"
code_advisory_tolerate=$?
set -e
if [[ "$code_advisory_tolerate" -ne 0 ]]; then
	eprint "Expected advisory failure to be tolerated by main review flow"
	cat "$tmpdir/stderr-advisory-tolerate" >&2
	exit 1
fi
if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/review.json" ]]; then
	eprint "Expected review.json to be created when advisory lane fails"
	exit 1
fi
if ! grep -q "advisory lane failed" "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/advisory.txt"; then
	eprint "Expected advisory fallback message when advisory lane engine fails"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/advisory.txt" >&2
	exit 1
fi
if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/advisory.stderr" ]]; then
	eprint "Expected advisory.stderr to be created when advisory lane runs"
	exit 1
fi
if ! grep -q "advisory simulated stderr" "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/advisory.stderr"; then
	eprint "Expected advisory stderr details to be preserved in advisory.stderr"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-tolerate/advisory.stderr" >&2
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-stale-check) >/dev/null

cat >"$tmpdir/codex-advisory-no-output-main-pass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi

if [[ ${1:-} != "exec" ]]; then
  exit 2
fi
shift

out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      out="$2"
      shift 2
      ;;
    -m|-c)
      shift 2
      ;;
    --sandbox)
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

if [[ -z "$out" ]]; then
  exit 2
fi

count_file="${CODEX_ADVISORY_NOOUT_COUNT_FILE:?}"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s' "$count" >"$count_file"

if [[ "$count" -eq 1 ]]; then
  exit 0
fi

mkdir -p "$(dirname "$out")"
cat >"$out" <<'JSON'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "advisory no-output fallback"
}
JSON
EOF
chmod +x "$tmpdir/codex-advisory-no-output-main-pass"

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_ADVISORY_NOOUT_COUNT_FILE="$tmpdir/advisory-noout-count" \
	CODEX_BIN="$tmpdir/codex-advisory-no-output-main-pass" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-stale-check) >/dev/null

if ! grep -q "advisory lane produced no output" "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-stale-check/advisory.txt"; then
	eprint "Expected advisory stale file to be replaced with no-output fallback message"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-stale-check/advisory.txt" >&2
	exit 1
fi

cat >"$tmpdir/codex-no-call-local" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
echo "engine should not be called on advisory self-reuse" >&2
exit 70
EOF
chmod +x "$tmpdir/codex-no-call-local"

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-self-reuse) >/dev/null

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-call-local" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-self-reuse) >/dev/null 2>"$tmpdir/stderr-advisory-self-reuse"
code_advisory_self_reuse=$?
set -e
if [[ "$code_advisory_self_reuse" -ne 0 ]]; then
	eprint "Expected advisory self-reuse to avoid same-file copy failure"
	cat "$tmpdir/stderr-advisory-self-reuse" >&2
	exit 1
fi
if ! grep -q '"reused": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-self-reuse/review-metadata.json"; then
	eprint "Expected reused=true for advisory self-reuse run"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-self-reuse/review-metadata.json" >&2
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-toggle) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-toggle/advisory.txt" ]]; then
	eprint "Expected advisory.txt to exist after advisory-enabled run"
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=0 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-toggle) >/dev/null

if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-toggle/advisory.txt" ]]; then
	eprint "Did not expect stale advisory.txt when advisory lane is disabled"
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-toggle/advisory.stderr" ]]; then
	eprint "Did not expect stale advisory.stderr when advisory lane is disabled"
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-toggle/advisory-prompt.txt" ]]; then
	eprint "Did not expect stale advisory-prompt.txt when advisory lane is disabled"
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=0 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-off-reuse) >/dev/null

printf '%s\n' 'stale advisory artifact' >"$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory.txt"
printf '%s\n' 'stale advisory stderr artifact' >"$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory.stderr"
printf '%s\n' 'stale advisory prompt artifact' >"$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory-prompt.txt"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=0 REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-call-local" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-advisory-off-reuse) >/dev/null 2>"$tmpdir/stderr-advisory-off-reuse"
code_advisory_off_reuse=$?
set -e
if [[ "$code_advisory_off_reuse" -ne 0 ]]; then
	eprint "Expected advisory-off reuse run to succeed without engine call"
	cat "$tmpdir/stderr-advisory-off-reuse" >&2
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory.txt" ]]; then
	eprint "Did not expect stale advisory.txt after advisory-off cache reuse"
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory.stderr" ]]; then
	eprint "Did not expect stale advisory.stderr after advisory-off cache reuse"
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory-off-reuse/advisory-prompt.txt" ]]; then
	eprint "Did not expect stale advisory-prompt.txt after advisory-off cache reuse"
	exit 1
fi

cat >"$tmpdir/codex-no-output" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
if [[ ${1:-} == "exec" ]]; then
  cat >/dev/null || true
  exit 0
fi
exit 2
EOF
chmod +x "$tmpdir/codex-no-output"

mkdir -p "$tmpdir/.agentic-sdd/reviews/issue-1/run-no-output"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/run-no-output/review.json"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-no-output" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-no-output) >/dev/null 2>"$tmpdir/stderr-no-output"
code_no_output=$?
set -e
if [[ "$code_no_output" -eq 0 ]]; then
	eprint "Expected no-output engine run to fail"
	exit 1
fi

no_output_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-no-output/review-metadata.json"
if [[ ! -f "$no_output_meta" ]]; then
	eprint "Expected failure metadata for no-output run"
	cat "$tmpdir/stderr-no-output" >&2
	exit 1
fi

if ! grep -q '"review_completed": false' "$no_output_meta"; then
	eprint "Expected review_completed=false in no-output metadata"
	cat "$no_output_meta" >&2
	exit 1
fi
if ! grep -q '"failure_reason": "no-output"' "$no_output_meta"; then
	eprint "Expected failure_reason=no-output in no-output metadata"
	cat "$no_output_meta" >&2
	exit 1
fi
if ! grep -q '"engine_stderr_summary":' "$no_output_meta"; then
	eprint "Expected engine_stderr_summary in no-output metadata"
	cat "$no_output_meta" >&2
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-no-output/review.json" ]]; then
	eprint "Expected stale review.json to be removed on no-output failure"
	exit 1
fi

cat >"$tmpdir/codex-invalid-json" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi

if [[ ${1:-} != "exec" ]]; then
  exit 2
fi
shift

out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -z "$out" ]]; then
  exit 2
fi

mkdir -p "$(dirname "$out")"
cat >"$out" <<'JSON'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved"
}
JSON
EOF
chmod +x "$tmpdir/codex-invalid-json"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-invalid-json" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-validation-fail) >/dev/null 2>"$tmpdir/stderr-validation-fail"
code_validation_fail=$?
set -e
if [[ "$code_validation_fail" -eq 0 ]]; then
	eprint "Expected schema validation failure run to fail"
	exit 1
fi

validation_fail_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-validation-fail/review-metadata.json"
if [[ ! -f "$validation_fail_meta" ]]; then
	eprint "Expected failure metadata for validation-failed run"
	cat "$tmpdir/stderr-validation-fail" >&2
	exit 1
fi
if ! grep -q '"failure_reason": "validation-failed"' "$validation_fail_meta"; then
	eprint "Expected failure_reason=validation-failed in metadata"
	cat "$validation_fail_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$validation_fail_meta"; then
	eprint "Expected review_completed=false in validation-failed metadata"
	cat "$validation_fail_meta" >&2
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-validation-fail/review.json" ]]; then
	eprint "Expected invalid review.json to be removed on validation failure"
	exit 1
fi

cat >"$tmpdir/codex-engine-exit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
if [[ ${1:-} == "exec" ]]; then
  cat >/dev/null || true
  exit 9
fi
exit 2
EOF
chmod +x "$tmpdir/codex-engine-exit"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-engine-exit" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-engine-exit) >/dev/null 2>"$tmpdir/stderr-engine-exit"
code_engine_exit=$?
set -e
if [[ "$code_engine_exit" -eq 0 ]]; then
	eprint "Expected engine-exit run to fail"
	exit 1
fi

engine_exit_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-engine-exit/review-metadata.json"
if [[ ! -f "$engine_exit_meta" ]]; then
	eprint "Expected failure metadata for engine-exit run"
	cat "$tmpdir/stderr-engine-exit" >&2
	exit 1
fi
if ! grep -q '"failure_reason": "engine-exit"' "$engine_exit_meta"; then
	eprint "Expected failure_reason=engine-exit in metadata"
	cat "$engine_exit_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$engine_exit_meta"; then
	eprint "Expected review_completed=false in engine-exit metadata"
	cat "$engine_exit_meta" >&2
	exit 1
fi
engine_runtime_ms_engine_exit="$(
	python3 - "$engine_exit_meta" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

v = data.get("engine_runtime_ms")
if isinstance(v, int) and v >= 0:
    print(v)
PY
)"
if [[ -z "$engine_runtime_ms_engine_exit" ]]; then
	eprint "Expected engine_runtime_ms to be a non-negative integer in engine-exit metadata"
	cat "$engine_exit_meta" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	MAX_DIFF_BYTES=1 CODEX_BIN="$tmpdir/codex-no-call" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-over-diff-budget) >/dev/null 2>"$tmpdir/stderr-diff-budget"
code_diff_budget=$?
set -e
if [[ "$code_diff_budget" -eq 0 ]]; then
	eprint "Expected failure when diff bytes exceed MAX_DIFF_BYTES"
	exit 1
fi
if ! grep -q "Diff bytes exceeded MAX_DIFF_BYTES" "$tmpdir/stderr-diff-budget"; then
	eprint "Expected diff budget error message, got:"
	cat "$tmpdir/stderr-diff-budget" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" SOT_MAX_CHARS=0 SOT="$(
	python3 - <<'PY'
print('S' * 12000)
PY
)" TESTS="not run: reason" DIFF_MODE=staged \
MAX_PROMPT_BYTES=500 CODEX_BIN="$tmpdir/codex-no-call" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-over-prompt-budget) >/dev/null 2>"$tmpdir/stderr-prompt-budget"
code_prompt_budget=$?
set -e
if [[ "$code_prompt_budget" -eq 0 ]]; then
	eprint "Expected failure when prompt bytes exceed MAX_PROMPT_BYTES"
	exit 1
fi
if ! grep -q "Prompt bytes exceeded MAX_PROMPT_BYTES" "$tmpdir/stderr-prompt-budget"; then
	eprint "Expected prompt budget error message, got:"
	cat "$tmpdir/stderr-prompt-budget" >&2
	exit 1
fi

cat >"$tmpdir/codex-no-call-early" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
echo "engine should not be called before prompt budget failure" >&2
exit 70
EOF
chmod +x "$tmpdir/codex-no-call-early"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" SOT_MAX_CHARS=0 SOT="$(
	python3 - <<'PY'
print('S' * 12000)
PY
)" TESTS="not run: reason" DIFF_MODE=staged REVIEW_CYCLE_ADVISORY_LANE=1 \
MAX_PROMPT_BYTES=500 CODEX_BIN="$tmpdir/codex-no-call-early" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-over-prompt-budget-advisory) >/dev/null 2>"$tmpdir/stderr-prompt-budget-advisory"
code_prompt_budget_advisory=$?
set -e
if [[ "$code_prompt_budget_advisory" -eq 0 ]]; then
	eprint "Expected advisory run to fail when prompt bytes exceed MAX_PROMPT_BYTES"
	exit 1
fi
if ! grep -q "Prompt bytes exceeded MAX_PROMPT_BYTES" "$tmpdir/stderr-prompt-budget-advisory"; then
	eprint "Expected prompt budget error for advisory run, got:"
	cat "$tmpdir/stderr-prompt-budget-advisory" >&2
	exit 1
fi
if grep -q "engine should not be called before prompt budget failure" "$tmpdir/stderr-prompt-budget-advisory"; then
	eprint "Did not expect advisory engine call before prompt budget fail-fast"
	cat "$tmpdir/stderr-prompt-budget-advisory" >&2
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-over-prompt-budget-advisory/advisory.stderr" ]]; then
	eprint "Did not expect advisory.stderr when prompt budget fail-fast exits before advisory execution"
	exit 1
fi

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" SOT_MAX_CHARS=0 SOT="$(
	python3 - <<'PY'
print('S' * 12000)
PY
)" TESTS="not run: reason" DIFF_MODE=staged REVIEW_CYCLE_ADVISORY_LANE=1 \
MAX_PROMPT_BYTES=0 MAX_ADVISORY_PROMPT_BYTES=500 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-over-advisory-prompt-budget) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-over-advisory-prompt-budget/review.json" ]]; then
	eprint "Expected main review to complete when only advisory prompt budget is exceeded"
	exit 1
fi
if ! grep -q "MAX_ADVISORY_PROMPT_BYTES" "$tmpdir/.agentic-sdd/reviews/issue-1/run-over-advisory-prompt-budget/advisory.txt"; then
	eprint "Expected advisory skip message to reference MAX_ADVISORY_PROMPT_BYTES"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-over-advisory-prompt-budget/advisory.txt" >&2
	exit 1
fi
if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/run-over-advisory-prompt-budget/advisory.stderr" ]]; then
	eprint "Did not expect advisory.stderr when advisory prompt budget prevents advisory execution"
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	MAX_DIFF_BYTES=08 CODEX_BIN="$tmpdir/codex-no-call" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-invalid-leading-zero-limit) >/dev/null 2>"$tmpdir/stderr-invalid-leading-zero-limit"
code_invalid_leading_zero_limit=$?
set -e
if [[ "$code_invalid_leading_zero_limit" -eq 0 ]]; then
	eprint "Expected MAX_DIFF_BYTES=08 run to fail on diff budget"
	cat "$tmpdir/stderr-invalid-leading-zero-limit" >&2
	exit 1
fi
if ! grep -q "Diff bytes exceeded MAX_DIFF_BYTES" "$tmpdir/stderr-invalid-leading-zero-limit"; then
	eprint "Expected diff budget message for MAX_DIFF_BYTES=08"
	cat "$tmpdir/stderr-invalid-leading-zero-limit" >&2
	exit 1
fi
if grep -q "value too great for base" "$tmpdir/stderr-invalid-leading-zero-limit"; then
	eprint "Did not expect bash octal parse error for MAX_DIFF_BYTES=08"
	cat "$tmpdir/stderr-invalid-leading-zero-limit" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=staged REVIEW_CYCLE_CACHE_POLICY=weird \
	"$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>"$tmpdir/stderr-policy-invalid"
code_policy_invalid=$?
set -e
if [[ "$code_policy_invalid" -eq 0 ]]; then
	eprint "Expected invalid REVIEW_CYCLE_CACHE_POLICY to fail"
	exit 1
fi
if ! grep -q "Invalid REVIEW_CYCLE_CACHE_POLICY" "$tmpdir/stderr-policy-invalid"; then
	eprint "Expected invalid cache policy error message, got:"
	cat "$tmpdir/stderr-policy-invalid" >&2
	exit 1
fi

seed_run="run-cache-seed"
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	CODEX_BIN="$tmpdir/codex" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 "$seed_run") >/dev/null

cat >"$tmpdir/codex-no-call" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
echo "engine should not be called on cache hit" >&2
exit 70
EOF
chmod +x "$tmpdir/codex-no-call"

hit_run="run-cache-hit"
set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 "$hit_run") >/dev/null 2>"$tmpdir/stderr-cache-hit"
code_cache_hit=$?
set -e
if [[ "$code_cache_hit" -ne 0 ]]; then
	eprint "Expected cache hit to reuse artifacts without calling engine"
	cat "$tmpdir/stderr-cache-hit" >&2
	exit 1
fi

if ! cmp -s "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"; then
	eprint "Expected cache-hit review.json to be reused from seed run"
	exit 1
fi

if ! grep -q '"reused": true' "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"; then
	eprint "Expected reused=true in cache-hit metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"reused_from_run": "run-cache-seed"' "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"; then
	eprint "Expected reused_from_run in cache-hit metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"cache_policy": "balanced"' "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"; then
	eprint "Expected cache_policy=balanced in review metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" >&2
	exit 1
fi

if ! grep -q '"reuse_reason": "cache-hit-balanced"' "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"; then
	eprint "Expected balanced cache-hit reason in metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" >&2
	exit 1
fi

if [[ -f "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/prompt.txt" ]]; then
	eprint "Expected cache-hit path to skip prompt generation"
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged MAX_PROMPT_BYTES=1 \
	REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-prompt-budget-miss) >/dev/null 2>"$tmpdir/stderr-cache-prompt-budget-miss"
code_cache_prompt_budget_miss=$?
set -e
if [[ "$code_cache_prompt_budget_miss" -eq 0 ]]; then
	eprint "Expected strict MAX_PROMPT_BYTES to force non-reuse"
	exit 1
fi
if ! grep -q "Prompt bytes exceeded MAX_PROMPT_BYTES" "$tmpdir/stderr-cache-prompt-budget-miss"; then
	eprint "Expected cache miss to fail fast when MAX_PROMPT_BYTES is stricter than cached prompt"
	cat "$tmpdir/stderr-cache-prompt-budget-miss" >&2
	exit 1
fi

cat >"$tmpdir/codex-no-version" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == "--version" ]]; then
  echo "no version" >&2
  exit 2
fi
echo "engine called due version unavailable" >&2
exit 71
EOF
chmod +x "$tmpdir/codex-no-version"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-version" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-no-version) >/dev/null 2>"$tmpdir/stderr-cache-no-version"
code_cache_no_version=$?
set -e
if [[ "$code_cache_no_version" -eq 0 ]]; then
	eprint "Expected missing engine version to force non-reuse"
	exit 1
fi
if ! grep -q "engine called due version unavailable" "$tmpdir/stderr-cache-no-version"; then
	eprint "Expected cache miss to execute engine when version is unavailable"
	cat "$tmpdir/stderr-cache-no-version" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged CONSTRAINTS="tight" \
	REVIEW_CYCLE_INCREMENTAL=1 CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-constraints-miss) >/dev/null 2>"$tmpdir/stderr-cache-constraints-miss"
code_cache_constraints_miss=$?
set -e
if [[ "$code_cache_constraints_miss" -eq 0 ]]; then
	eprint "Expected constraints change to force non-reuse"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-constraints-miss"; then
	eprint "Expected cache miss to execute engine when constraints changed"
	cat "$tmpdir/stderr-cache-constraints-miss" >&2
	exit 1
fi

python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["status"] = "Blocked"
data["findings"] = [
    {
        "title": "Blocked cache sample",
        "body": "cached blocked response for balanced reuse test",
        "priority": "P1",
        "code_location": {
            "repo_relative_path": "hello.txt",
            "line_range": {"start": 1, "end": 1},
        },
    }
]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-blocked) >/dev/null 2>"$tmpdir/stderr-cache-blocked"
code_cache_blocked=$?
set -e
if [[ "$code_cache_blocked" -eq 0 ]]; then
	eprint "Expected blocked cached review to be non-reusable"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-blocked"; then
	eprint "Expected cache miss to execute engine when cached status is blocked"
	cat "$tmpdir/stderr-cache-blocked" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=balanced CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-blocked-balanced) >/dev/null 2>"$tmpdir/stderr-cache-blocked-balanced"
code_cache_blocked_balanced=$?
set -e
if [[ "$code_cache_blocked_balanced" -ne 0 ]]; then
	eprint "Expected blocked cached review to be reusable in balanced policy"
	cat "$tmpdir/stderr-cache-blocked-balanced" >&2
	exit 1
fi
if ! grep -q '"reused": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-blocked-balanced/review-metadata.json"; then
	eprint "Expected reused=true for balanced blocked cache hit"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-blocked-balanced/review-metadata.json" >&2
	exit 1
fi
if ! grep -q '"reuse_reason": "cache-hit-balanced"' "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-blocked-balanced/review-metadata.json"; then
	eprint "Expected balanced cache-hit reason in metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-blocked-balanced/review-metadata.json" >&2
	exit 1
fi

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["status"] = "Question"
data["findings"] = []
data["questions"] = ["Please confirm expected cache policy behavior"]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=balanced CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-question-balanced) >/dev/null 2>"$tmpdir/stderr-cache-question-balanced"
code_cache_question_balanced=$?
set -e
if [[ "$code_cache_question_balanced" -ne 0 ]]; then
	eprint "Expected question cached review to be reusable in balanced policy"
	cat "$tmpdir/stderr-cache-question-balanced" >&2
	exit 1
fi
if ! grep -q '"reused": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-question-balanced/review-metadata.json"; then
	eprint "Expected reused=true for balanced question cache hit"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-question-balanced/review-metadata.json" >&2
	exit 1
fi
if ! grep -q '"reuse_reason": "cache-hit-balanced"' "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-question-balanced/review-metadata.json"; then
	eprint "Expected balanced cache-hit reason in question metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-question-balanced/review-metadata.json" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=off CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-policy-off) >/dev/null 2>"$tmpdir/stderr-cache-policy-off"
code_cache_policy_off=$?
set -e
if [[ "$code_cache_policy_off" -eq 0 ]]; then
	eprint "Expected REVIEW_CYCLE_CACHE_POLICY=off to force full execution"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-policy-off"; then
	eprint "Expected policy=off to skip reuse and call engine"
	cat "$tmpdir/stderr-cache-policy-off" >&2
	exit 1
fi

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data.pop("advisory_lane_enabled", None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

printf '%s' "$hit_run" >"$tmpdir/.agentic-sdd/reviews/issue-1/.current_run"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-missing-advisory-flag) >/dev/null 2>"$tmpdir/stderr-cache-missing-advisory-flag"
code_cache_missing_advisory_flag=$?
set -e
if [[ "$code_cache_missing_advisory_flag" -ne 0 ]]; then
	eprint "Expected missing advisory_lane_enabled to fallback to advisory-off compatibility"
	cat "$tmpdir/stderr-cache-missing-advisory-flag" >&2
	exit 1
fi
if ! grep -q '"reused": true' "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-missing-advisory-flag/review-metadata.json"; then
	eprint "Expected reused=true when advisory_lane_enabled is absent in cached metadata"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-cache-missing-advisory-flag/review-metadata.json" >&2
	exit 1
fi

printf '%s' "$hit_run" >"$tmpdir/.agentic-sdd/reviews/issue-1/.current_run"

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data.pop("script_semantics_version", None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-missing-script-semantics) >/dev/null 2>"$tmpdir/stderr-cache-missing-script-semantics"
code_cache_missing_script_semantics=$?
set -e
if [[ "$code_cache_missing_script_semantics" -eq 0 ]]; then
	eprint "Expected missing script_semantics_version to force non-reuse"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-missing-script-semantics"; then
	eprint "Expected cache miss to execute engine when script_semantics_version is missing"
	cat "$tmpdir/stderr-cache-missing-script-semantics" >&2
	exit 1
fi

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["tests_exit_code"] = 1
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-review-completed-invalid) >/dev/null 2>"$tmpdir/stderr-cache-review-completed-invalid"
code_cache_review_completed_invalid=$?
set -e
if [[ "$code_cache_review_completed_invalid" -eq 0 ]]; then
	eprint "Expected invalid review_completed to force non-reuse"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-review-completed-invalid"; then
	eprint "Expected cache miss to execute engine when review_completed is invalid"
	cat "$tmpdir/stderr-cache-review-completed-invalid" >&2
	exit 1
fi

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["tests_exit_code"] = 0
data["review_completed"] = "false"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-review-completed-string) >/dev/null 2>"$tmpdir/stderr-cache-review-completed-string"
code_cache_review_completed_string=$?
set -e
if [[ "$code_cache_review_completed_string" -eq 0 ]]; then
	eprint "Expected non-boolean review_completed to force non-reuse"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-review-completed-string"; then
	eprint "Expected cache miss to execute engine when review_completed is non-boolean"
	cat "$tmpdir/stderr-cache-review-completed-string" >&2
	exit 1
fi

cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review.json"
cp -p "$tmpdir/.agentic-sdd/reviews/issue-1/$seed_run/review-metadata.json" "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json"
python3 - "$tmpdir/.agentic-sdd/reviews/issue-1/$hit_run/review-metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["tests_exit_code"] = 1
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_INCREMENTAL=1 REVIEW_CYCLE_CACHE_POLICY=strict CODEX_BIN="$tmpdir/codex-no-call" MODEL=seed-model REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-cache-tests-failed) >/dev/null 2>"$tmpdir/stderr-cache-tests-failed"
code_cache_tests_failed=$?
set -e
if [[ "$code_cache_tests_failed" -eq 0 ]]; then
	eprint "Expected tests-failed cached review to be non-reusable"
	exit 1
fi
if ! grep -q "engine should not be called on cache hit" "$tmpdir/stderr-cache-tests-failed"; then
	eprint "Expected cache miss to execute engine when cached tests_exit_code is nonzero"
	cat "$tmpdir/stderr-cache-tests-failed" >&2
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
long_sot="$(
	python3 - <<'PY'
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

size=$(wc -c <"$tmpdir/.agentic-sdd/reviews/issue-1/run3/sot.txt" | tr -d ' ')
if [[ "$size" -gt 3000 ]]; then
	eprint "Expected sot.txt size <= 3000, got: $size"
	exit 1
fi

# Fail-fast when referenced PRD is missing
cat >"$tmpdir/issue-missing.md" <<'EOF'
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

cat >"$tmpdir/bash-env-inject.sh" <<'EOF'
echo injected-from-bashenv >&2
EOF

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" DIFF_MODE=staged \
	BASH_ENV="$tmpdir/bash-env-inject.sh" \
	TEST_COMMAND='python3 -c "print(\"ok\")"' TESTS="" TEST_STDERR_POLICY=fail \
	CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-stderr-bashenv) >/dev/null 2>"$tmpdir/stderr-stderr-bashenv"
code_stderr_bashenv=$?
set -e
if [[ "$code_stderr_bashenv" -ne 0 ]]; then
	eprint "Expected success when BASH_ENV is ignored for TEST_COMMAND execution"
	cat "$tmpdir/stderr-stderr-bashenv" >&2
	exit 1
fi
if grep -q "injected-from-bashenv" "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-bashenv/tests.stderr"; then
	eprint "Did not expect BASH_ENV side effects in tests.stderr"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-stderr-bashenv/tests.stderr" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" DIFF_MODE=staged \
	TEST_COMMAND='python3 -c "import sys; sys.stdout.buffer.write(b\"ok\\xff\\n\")"' TESTS="" \
	CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-tests-nonutf8) >/dev/null 2>"$tmpdir/stderr-tests-nonutf8"
code_tests_nonutf8=$?
set -e
if [[ "$code_tests_nonutf8" -ne 0 ]]; then
	eprint "Expected success when tests output contains non-UTF-8 bytes"
	cat "$tmpdir/stderr-tests-nonutf8" >&2
	exit 1
fi
if ! grep -q '"tests_fingerprint":' "$tmpdir/.agentic-sdd/reviews/issue-1/run-tests-nonutf8/review-metadata.json"; then
	eprint "Expected tests_fingerprint in metadata for non-UTF-8 test output"
	cat "$tmpdir/.agentic-sdd/reviews/issue-1/run-tests-nonutf8/review-metadata.json" >&2
	exit 1
fi

# Validator smoke test
cat >"$tmpdir/review.json" <<'EOF'
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
cat >"$tmpdir/review-ja.json" <<'EOF'
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
cat >"$tmpdir/review-blocked.json" <<'EOF'
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
cat >"$tmpdir/review-bad-priority.json" <<'EOF'
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
cat >"$tmpdir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "claude-stub 1.0.0"
  exit 0
fi

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
echo "claude-change" >>"$tmpdir/hello.txt"
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

cat >"$tmpdir/claude-default-model" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "claude-stub 1.0.0"
  exit 0
fi

seen_model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      shift
      ;;
    --model)
      seen_model="${2:-}"
      shift 2 2>/dev/null || shift
      ;;
    --output-format|--betas|--json-schema)
      shift 2 2>/dev/null || shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${CLAUDE_MODEL_CAPTURE:-}" ]]; then
  printf '%s\n' "$seen_model" >"$CLAUDE_MODEL_CAPTURE"
fi

cat >/dev/null || true

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
    "overall_explanation": "claude default model stub"
  }
}
JSON
EOF
chmod +x "$tmpdir/claude-default-model"

default_model_capture="$tmpdir/claude-default-model.seen"
rm -f "$default_model_capture"
(cd "$tmpdir" && env -u CLAUDE_MODEL GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_ENGINE=claude CLAUDE_BIN="$tmpdir/claude-default-model" CLAUDE_MODEL_CAPTURE="$default_model_capture" \
	"$review_cycle_sh" issue-claude run-default-model) >/dev/null

if [[ ! -f "$default_model_capture" ]]; then
	eprint "Expected Claude default model capture file to be created"
	exit 1
fi

if [[ "$(cat "$default_model_capture")" != "opus" ]]; then
	eprint "Expected default Claude model to be opus"
	cat "$default_model_capture" >&2
	exit 1
fi

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-claude/run-default-model/review.json" ]]; then
	eprint "Expected review.json to be created when using default Claude model"
	exit 1
fi

schema_path_with_quote="${tmpdir}/schema'quoted.json"
cp -p "$schema_src" "$schema_path_with_quote"
echo "claude-quoted-schema" >>"$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt

(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_ENGINE=claude CLAUDE_BIN="$tmpdir/claude" CLAUDE_MODEL=stub SCHEMA_PATH="$schema_path_with_quote" \
	"$review_cycle_sh" issue-claude run-schema-quoted) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-claude/run-schema-quoted/review.json" ]]; then
	eprint "Expected review.json to be created when SCHEMA_PATH contains single quote"
	exit 1
fi

if ! grep -q "claude stub wrapped" "$tmpdir/.agentic-sdd/reviews/issue-claude/run-schema-quoted/review.json"; then
	eprint "Expected Claude stub wrapped output for quoted SCHEMA_PATH run"
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
cat >"$tmpdir/claude-error" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "claude-stub 1.0.0"
  exit 0
fi
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

claude_err_meta="$tmpdir/.agentic-sdd/reviews/issue-claude-err/run1/review-metadata.json"
if [[ ! -f "$claude_err_meta" ]]; then
	eprint "Expected failure metadata for Claude extract error"
	exit 1
fi
if ! grep -q '"failure_reason": "extract-structured-output"' "$claude_err_meta"; then
	eprint "Expected failure_reason=extract-structured-output in metadata"
	cat "$claude_err_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$claude_err_meta"; then
	eprint "Expected review_completed=false in extract-structured-output metadata"
	cat "$claude_err_meta" >&2
	exit 1
fi
engine_runtime_ms_claude_err="$(
	python3 - "$claude_err_meta" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

v = data.get("engine_runtime_ms")
if isinstance(v, int) and v >= 0:
    print(v)
PY
)"
if [[ -z "$engine_runtime_ms_claude_err" ]]; then
	eprint "Expected engine_runtime_ms to be a non-negative integer for Claude extract failure"
	cat "$claude_err_meta" >&2
	exit 1
fi

# Issue #127 hybrid review-cycle/create-pr compatibility coverage.
# AC4 (docs) は .agent/commands/create-pr.md で対応済み。以下は AC1-AC3 のテスト。

# AC1: Schema v3 validation (advisory OFF/ON)
run1_review_json="$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json"
run1_review_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run1/review-metadata.json"
run_advisory_review_json="$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/review.json"
run_advisory_review_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-advisory/review-metadata.json"

python3 "$validator_py" "$run1_review_json" --scope-id issue-1 >/dev/null
python3 "$validator_py" "$run_advisory_review_json" --scope-id issue-1 >/dev/null

if grep -q '"advisory_lane_enabled": true' "$run1_review_meta"; then
	eprint "AC1: Expected advisory_lane_enabled to be false/absent for advisory OFF run"
	cat "$run1_review_meta" >&2
	exit 1
fi
if ! grep -q '"advisory_lane_enabled": true' "$run_advisory_review_meta"; then
	eprint "AC1: Expected advisory_lane_enabled=true for advisory ON run"
	cat "$run_advisory_review_meta" >&2
	exit 1
fi

if ! python3 - "$run1_review_json" "$run_advisory_review_json" <<'PY'; then
import json
import sys

required = {
    "schema_version",
    "scope_id",
    "status",
    "findings",
    "questions",
    "overall_explanation",
}

for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if data.get("schema_version") != 3:
        raise SystemExit(1)
    if not required.issubset(set(data.keys())):
        raise SystemExit(2)
PY
	eprint "AC1: Expected schema_version=3 and all required top-level keys in both review.json files"
	cat "$run1_review_json" >&2
	cat "$run_advisory_review_json" >&2
	exit 1
fi

# AC2: create-pr metadata hard check (advisory OFF/ON)
create_pr_sh="${repo_root}/scripts/create-pr.sh"
if [[ ! -f "$create_pr_sh" || ! -x "$create_pr_sh" ]]; then
	eprint "Missing script or not executable: $create_pr_sh"
	exit 1
fi
compat_origin="$tmpdir/compat-origin.git"
compat_repo="$tmpdir/compat-repo"
compat_bin_dir="$tmpdir/compat-bin"
compat_gh_stub="$compat_bin_dir/gh"
compat_issue_body="$compat_repo/issue-body.md"

git init -q --bare "$compat_origin"
mkdir -p "$compat_repo"
git -C "$compat_repo" init -q
git -C "$compat_repo" remote add origin "$compat_origin"
mkdir -p "$compat_repo/.agent/schemas"
cp -p "$schema_src" "$compat_repo/.agent/schemas/review.json"
mkdir -p "$compat_repo/docs/prd" "$compat_repo/docs/epics"
cat >"$compat_repo/docs/prd/prd.md" <<'EOF'
# PRD: Compat

## 1. Purpose

compat
EOF
cat >"$compat_repo/docs/epics/epic.md" <<'EOF'
# Epic: Compat

## 1. Scope

compat
EOF

cat >"$compat_repo/hello.txt" <<'EOF'
hello
EOF
git -C "$compat_repo" add hello.txt
git -C "$compat_repo" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$compat_repo" branch -M main
git -C "$compat_repo" push -u origin main >/dev/null

git -C "$compat_repo" switch -c feature/issue-1-compat -q
echo "compat-change" >>"$compat_repo/hello.txt"
git -C "$compat_repo" add hello.txt
git -C "$compat_repo" -c user.name=test -c user.email=test@example.com commit -m "compat change" -q

compat_head_sha="$(git -C "$compat_repo" rev-parse HEAD)"
compat_base_sha="$(git -C "$compat_repo" rev-parse main)"

cat >"$compat_issue_body" <<'EOF'
## Background

- Epic: docs/epics/epic.md
- PRD: docs/prd/prd.md

## Acceptance Criteria

- [ ] AC1: compat
EOF

mkdir -p "$compat_bin_dir"
cat >"$compat_gh_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "issue" && "${2:-}" == "develop" ]]; then
  printf 'feature/issue-1-compat\thttps://example.com\n'; exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  printf '{"title":"compat test","url":"https://example.com"}\n'; exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then printf '[]\n'; exit 0; fi
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then echo "no open PR" >&2; exit 1; fi
if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then printf 'https://example.com/pr/1\n'; exit 0; fi
echo "compat_gh_stub: unexpected args: $*" >&2; exit 64
EOF
chmod +x "$compat_gh_stub"

compat_write_test_review() {
	local run_id="$1"
	local review_root="$compat_repo/.agentic-sdd/test-reviews/issue-1"
	mkdir -p "$review_root/$run_id"
	cat >"$review_root/$run_id/test-review.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "compat test-review"
}
EOF
	cat >"$review_root/$run_id/test-review-metadata.json" <<EOF
{
  "head_sha": "${compat_head_sha}",
  "base_ref": "main",
  "base_sha": "${compat_base_sha}",
  "diff_mode": "range"
}
EOF
	printf '%s\n' "$run_id" >"$review_root/.current_run"
}

(cd "$compat_repo" && GH_ISSUE_BODY_FILE="$compat_issue_body" TESTS="not run: reason" DIFF_MODE=range BASE_REF=main \
	REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-compat-off) >/dev/null

compat_meta_off="$compat_repo/.agentic-sdd/reviews/issue-1/run-compat-off/review-metadata.json"
if ! grep -q '"diff_source": "range"' "$compat_meta_off"; then
	eprint "AC2: Expected diff_source=range in advisory OFF compat metadata"
	cat "$compat_meta_off" >&2
	exit 1
fi
if ! grep -q "\"head_sha\": \"${compat_head_sha}\"" "$compat_meta_off"; then
	eprint "AC2: Expected head_sha to match HEAD for advisory OFF compat metadata"
	cat "$compat_meta_off" >&2
	exit 1
fi
if ! grep -q "\"base_sha\": \"${compat_base_sha}\"" "$compat_meta_off"; then
	eprint "AC2: Expected base_sha to match main for advisory OFF compat metadata"
	cat "$compat_meta_off" >&2
	exit 1
fi
compat_write_test_review run-compat-off

if ! (cd "$compat_repo" && PATH="$compat_bin_dir:$PATH" "$create_pr_sh" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr-create-pr-compat-off"; then
	eprint "AC2: Expected create-pr dry-run success with advisory OFF review metadata"
	cat "$tmpdir/stderr-create-pr-compat-off" >&2
	exit 1
fi

(cd "$compat_repo" && GH_ISSUE_BODY_FILE="$compat_issue_body" TESTS="not run: reason" DIFF_MODE=range BASE_REF=main \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-compat-on) >/dev/null

compat_meta_on="$compat_repo/.agentic-sdd/reviews/issue-1/run-compat-on/review-metadata.json"
if ! grep -q '"diff_source": "range"' "$compat_meta_on"; then
	eprint "AC2: Expected diff_source=range in advisory ON compat metadata"
	cat "$compat_meta_on" >&2
	exit 1
fi
if ! grep -q "\"head_sha\": \"${compat_head_sha}\"" "$compat_meta_on"; then
	eprint "AC2: Expected head_sha to match HEAD for advisory ON compat metadata"
	cat "$compat_meta_on" >&2
	exit 1
fi
if ! grep -q "\"base_sha\": \"${compat_base_sha}\"" "$compat_meta_on"; then
	eprint "AC2: Expected base_sha to match main for advisory ON compat metadata"
	cat "$compat_meta_on" >&2
	exit 1
fi
compat_write_test_review run-compat-on

if ! (cd "$compat_repo" && PATH="$compat_bin_dir:$PATH" "$create_pr_sh" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr-create-pr-compat-on"; then
	eprint "AC2: Expected create-pr dry-run success with advisory ON review metadata"
	cat "$tmpdir/stderr-create-pr-compat-on" >&2
	exit 1
fi

# AC3: timeout/no-output/engine-exit fail-fast regression (advisory ON)
set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-no-output" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-noout-advisory-on) >/dev/null 2>"$tmpdir/stderr-noout-advisory-on"
code_noout_advisory_on=$?
set -e
if [[ "$code_noout_advisory_on" -eq 0 ]]; then
	eprint "AC3: Expected no-output run to fail when advisory lane is enabled"
	exit 1
fi

noout_advisory_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-noout-advisory-on/review-metadata.json"
if ! grep -q '"failure_reason": "no-output"' "$noout_advisory_meta"; then
	eprint "AC3: Expected failure_reason=no-output for advisory no-output run"
	cat "$noout_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$noout_advisory_meta"; then
	eprint "AC3: Expected review_completed=false for advisory no-output run"
	cat "$noout_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"advisory_lane_enabled": true' "$noout_advisory_meta"; then
	eprint "AC3: Expected advisory_lane_enabled=true for advisory no-output run"
	cat "$noout_advisory_meta" >&2
	exit 1
fi

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-engine-exit" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-engine-exit-advisory-on) >/dev/null 2>"$tmpdir/stderr-engine-exit-advisory-on"
code_engine_exit_advisory_on=$?
set -e
if [[ "$code_engine_exit_advisory_on" -eq 0 ]]; then
	eprint "AC3: Expected engine-exit run to fail when advisory lane is enabled"
	exit 1
fi

engine_exit_advisory_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-engine-exit-advisory-on/review-metadata.json"
if ! grep -q '"failure_reason": "engine-exit"' "$engine_exit_advisory_meta"; then
	eprint "AC3: Expected failure_reason=engine-exit for advisory engine-exit run"
	cat "$engine_exit_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$engine_exit_advisory_meta"; then
	eprint "AC3: Expected review_completed=false for advisory engine-exit run"
	cat "$engine_exit_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"advisory_lane_enabled": true' "$engine_exit_advisory_meta"; then
	eprint "AC3: Expected advisory_lane_enabled=true for advisory engine-exit run"
	cat "$engine_exit_advisory_meta" >&2
	exit 1
fi

# AC3 (continued): timeout fail-fast with advisory ON.
# review-cycle.sh treats timeout as engine-exit (timeout/gtimeout exit 124).
# Verify that exit-code 124 (simulating EXEC_TIMEOUT_SEC) is still fail-fast.
cat >"$tmpdir/codex-timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == "--version" ]]; then
  printf '%s\n' "codex-stub 1.0.0"
  exit 0
fi
if [[ ${1:-} == "exec" ]]; then
  cat >/dev/null || true
  exit 124
fi
exit 2
EOF
chmod +x "$tmpdir/codex-timeout"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" TESTS="not run: reason" DIFF_MODE=staged \
	REVIEW_CYCLE_ADVISORY_LANE=1 REVIEW_CYCLE_INCREMENTAL=0 CODEX_BIN="$tmpdir/codex-timeout" MODEL=stub REASONING_EFFORT=low \
	"$review_cycle_sh" issue-1 run-timeout-advisory-on) >/dev/null 2>"$tmpdir/stderr-timeout-advisory-on"
code_timeout_advisory_on=$?
set -e
if [[ "$code_timeout_advisory_on" -eq 0 ]]; then
	eprint "AC3: Expected timeout run to fail when advisory lane is enabled"
	exit 1
fi

timeout_advisory_meta="$tmpdir/.agentic-sdd/reviews/issue-1/run-timeout-advisory-on/review-metadata.json"
if ! grep -q '"failure_reason": "engine-exit"' "$timeout_advisory_meta"; then
	eprint "AC3: Expected failure_reason=engine-exit for advisory timeout run (exit 124)"
	cat "$timeout_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"review_completed": false' "$timeout_advisory_meta"; then
	eprint "AC3: Expected review_completed=false for advisory timeout run"
	cat "$timeout_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"advisory_lane_enabled": true' "$timeout_advisory_meta"; then
	eprint "AC3: Expected advisory_lane_enabled=true for advisory timeout run"
	cat "$timeout_advisory_meta" >&2
	exit 1
fi
if ! grep -q '"engine_exit_code": 124' "$timeout_advisory_meta"; then
	eprint "AC3: Expected engine_exit_code=124 for advisory timeout run"
	cat "$timeout_advisory_meta" >&2
	exit 1
fi
eprint "OK: scripts/tests/test-review-cycle.sh"
