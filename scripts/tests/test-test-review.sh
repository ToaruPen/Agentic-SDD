#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_src="$repo_root/scripts/test-review.sh"

if [[ ! -x "$script_src" ]]; then
  eprint "Missing script or not executable: $script_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-test-review)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q
cat > "$tmpdir/hello.sh" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
chmod +x "$tmpdir/hello.sh"
mkdir -p "$tmpdir/scripts/tests"
cat > "$tmpdir/scripts/tests/test-existing.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ 1 -eq 1 ]]
EOF
chmod +x "$tmpdir/scripts/tests/test-existing.sh"
git -C "$tmpdir" add hello.sh scripts/tests/test-existing.sh
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir" branch -M main

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=worktree "$script_src" issue-1 run-empty-diff) >/dev/null 2>"$tmpdir/stderr-empty-diff"
code_empty_diff=$?
set -e
if [[ "$code_empty_diff" -eq 0 ]]; then
  eprint "Expected empty diff to block"
  exit 1
fi
empty_diff_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-empty-diff/test-review.json"
status_empty_diff="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$empty_diff_json")"
if [[ "$status_empty_diff" != "Blocked" ]]; then
  eprint "Expected Blocked status for empty diff, got: $status_empty_diff"
  exit 1
fi

set +e
(cd "$tmpdir" && env -u TEST_REVIEW_PREFLIGHT_COMMAND "$script_src" issue-1 run-missing-pref) >/dev/null 2>"$tmpdir/stderr-missing"
code_missing=$?
set -e
if [[ "$code_missing" -eq 0 ]]; then
  eprint "Expected missing preflight command to fail"
  exit 1
fi
if ! grep -q "TEST_REVIEW_PREFLIGHT_COMMAND is required" "$tmpdir/stderr-missing"; then
  eprint "Expected missing preflight error message"
  cat "$tmpdir/stderr-missing" >&2
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' "$script_src" issue-1 '../run-escape') >/dev/null 2>"$tmpdir/stderr-invalid-run-id"
code_invalid_run_id=$?
set -e
if [[ "$code_invalid_run_id" -eq 0 ]]; then
  eprint "Expected invalid run-id to fail"
  exit 1
fi
if ! grep -q "Invalid run-id" "$tmpdir/stderr-invalid-run-id"; then
  eprint "Expected invalid run-id error message"
  cat "$tmpdir/stderr-invalid-run-id" >&2
  exit 1
fi

echo "code-change" >> "$tmpdir/hello.sh"
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 7"' TEST_REVIEW_DIFF_MODE=worktree "$script_src" issue-1 run-preflight-fail) >/dev/null 2>"$tmpdir/stderr-prefail"
code_prefail=$?
set -e
if [[ "$code_prefail" -eq 0 ]]; then
  eprint "Expected preflight failure to block"
  exit 1
fi
pref_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-preflight-fail/test-review.json"
if [[ ! -f "$pref_json" ]]; then
  eprint "Expected test-review.json for preflight failure"
  exit 1
fi
status_pref="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$pref_json")"
if [[ "$status_pref" != "Blocked" ]]; then
  eprint "Expected Blocked status for preflight failure, got: $status_pref"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=worktree "$script_src" issue-1 run-no-tests) >/dev/null 2>"$tmpdir/stderr-no-tests"
code_no_tests=$?
set -e
if [[ "$code_no_tests" -eq 0 ]]; then
  eprint "Expected no-test-change case to block"
  exit 1
fi
no_tests_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-no-tests/test-review.json"
status_no_tests="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$no_tests_json")"
if [[ "$status_no_tests" != "Blocked" ]]; then
  eprint "Expected Blocked status for no test changes, got: $status_no_tests"
  exit 1
fi

git -C "$tmpdir" add hello.sh
rm -f "$tmpdir"/stderr-*
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=auto "$script_src" issue-1 run-no-tests-auto) >/dev/null 2>/dev/null
code_no_tests_auto=$?
set -e
if [[ "$code_no_tests_auto" -eq 0 ]]; then
  eprint "Expected auto diff mode to block when staged code has no tests"
  exit 1
fi
no_tests_auto_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-no-tests-auto/test-review.json"
status_no_tests_auto="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$no_tests_auto_json")"
if [[ "$status_no_tests_auto" != "Blocked" ]]; then
  eprint "Expected Blocked status for auto no-test changes, got: $status_no_tests_auto"
  exit 1
fi

echo "extra-unstaged" >> "$tmpdir/hello.sh"
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=auto "$script_src" issue-1 run-auto-mixed-diff) >/dev/null 2>"$tmpdir/stderr-auto-mixed"
code_auto_mixed=$?
set -e
if [[ "$code_auto_mixed" -eq 0 ]]; then
  eprint "Expected auto mode to fail when staged and unstaged diffs coexist"
  exit 1
fi
if ! grep -q "TEST_REVIEW_DIFF_MODE=auto detected both staged and unstaged diffs" "$tmpdir/stderr-auto-mixed"; then
  eprint "Expected auto mixed diff error message"
  cat "$tmpdir/stderr-auto-mixed" >&2
  exit 1
fi

git -C "$tmpdir" add hello.sh

git -C "$tmpdir" add hello.sh
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=worktree "$script_src" issue-1 run-no-tests-staged-worktree) >/dev/null 2>"$tmpdir/stderr-no-tests-staged-worktree"
code_no_tests_staged_worktree=$?
set -e
if [[ "$code_no_tests_staged_worktree" -eq 0 ]]; then
  eprint "Expected staged no-test-change case to block in worktree mode"
  exit 1
fi
no_tests_staged_worktree_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-no-tests-staged-worktree/test-review.json"
status_no_tests_staged_worktree="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$no_tests_staged_worktree_json")"
if [[ "$status_no_tests_staged_worktree" != "Blocked" ]]; then
  eprint "Expected Blocked status for staged no test changes in worktree mode, got: $status_no_tests_staged_worktree"
  exit 1
fi

rm -f "$tmpdir/scripts/tests/test-existing.sh"
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=worktree "$script_src" issue-1 run-no-tests-deleted-test) >/dev/null 2>"$tmpdir/stderr-no-tests-deleted-test"
code_no_tests_deleted_test=$?
set -e
if [[ "$code_no_tests_deleted_test" -eq 0 ]]; then
  eprint "Expected deleted-test-only change not to satisfy test update gate"
  exit 1
fi
no_tests_deleted_test_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-no-tests-deleted-test/test-review.json"
status_no_tests_deleted_test="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$no_tests_deleted_test_json")"
if [[ "$status_no_tests_deleted_test" != "Blocked" ]]; then
  eprint "Expected Blocked status when only deleted tests accompany code changes, got: $status_no_tests_deleted_test"
  exit 1
fi

cat > "$tmpdir/scripts/tests/focused.spec.ts" <<'EOF'
describe.only('focused', () => {
  it('runs one test', () => {})
})
EOF
git -C "$tmpdir" add scripts/tests/focused.spec.ts
cat > "$tmpdir/scripts/tests/focused.spec.ts" <<'EOF'
describe('focused', () => {
  it('runs one test', () => {})
})
EOF
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-focused-staged) >/dev/null 2>"$tmpdir/stderr-focused-staged"
code_focused_staged=$?
set -e
if [[ "$code_focused_staged" -eq 0 ]]; then
  eprint "Expected staged focused test marker to block"
  exit 1
fi
focused_staged_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-focused-staged/test-review.json"
status_focused_staged="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$focused_staged_json")"
if [[ "$status_focused_staged" != "Blocked" ]]; then
  eprint "Expected Blocked status for staged focused marker, got: $status_focused_staged"
  exit 1
fi

cat > "$tmpdir/scripts/tests/focused.spec.ts" <<'EOF'
describe('focused', () => {
  fit('runs one test', () => {})
})
EOF
set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-focused-fit-staged) >/dev/null 2>"$tmpdir/stderr-focused-fit-staged"
code_focused_fit_staged=$?
set -e
if [[ "$code_focused_fit_staged" -eq 0 ]]; then
  eprint "Expected staged fit marker to block"
  exit 1
fi
focused_fit_staged_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-focused-fit-staged/test-review.json"
status_focused_fit_staged="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$focused_fit_staged_json")"
if [[ "$status_focused_fit_staged" != "Blocked" ]]; then
  eprint "Expected Blocked status for staged fit marker, got: $status_focused_fit_staged"
  exit 1
fi

cat > "$tmpdir/scripts/tests/focused.spec.ts" <<'EOF'
describe('focused', () => {
  it('runs one test', () => {})
})
EOF
git -C "$tmpdir" add scripts/tests/focused.spec.ts

mkdir -p "$tmpdir/tests" "$tmpdir/docs"
cat > "$tmpdir/tests/test_py_sample.py" <<'EOF'
def test_sample():
    assert True
EOF
cat > "$tmpdir/docs/notes.md" <<'EOF'
example: describe.only('snippet')
EOF
git -C "$tmpdir" add hello.sh tests/test_py_sample.py docs/notes.md

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-approved) >/dev/null 2>"$tmpdir/stderr-approved"
code_approved=$?
set -e
if [[ "$code_approved" -ne 0 ]]; then
  eprint "Expected approved run to succeed"
  cat "$tmpdir/stderr-approved" >&2
  exit 1
fi

approved_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-approved/test-review.json"
approved_meta="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-approved/test-review-metadata.json"
if [[ ! -f "$approved_json" || ! -f "$approved_meta" ]]; then
  eprint "Expected approved artifacts to exist"
  exit 1
fi
status_approved="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$approved_json")"
if [[ "$status_approved" != "Approved" ]]; then
  eprint "Expected Approved status, got: $status_approved"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DYNAMIC_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-pass) >/dev/null 2>"$tmpdir/stderr-dynamic-pass"
code_dynamic_pass=$?
set -e
if [[ "$code_dynamic_pass" -ne 0 ]]; then
  eprint "Expected dynamic pass run to succeed"
  cat "$tmpdir/stderr-dynamic-pass" >&2
  exit 1
fi
dynamic_pass_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-pass/test-review.json"
dynamic_pass_meta="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-pass/test-review-metadata.json"
status_dynamic_pass="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$dynamic_pass_json")"
if [[ "$status_dynamic_pass" != "Approved" ]]; then
  eprint "Expected Approved status for dynamic pass, got: $status_dynamic_pass"
  exit 1
fi
dynamic_enabled="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("dynamic_command_enabled"))' "$dynamic_pass_meta")"
dynamic_exit_code="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("dynamic_command_exit_code"))' "$dynamic_pass_meta")"
if [[ "$dynamic_enabled" != "True" || "$dynamic_exit_code" != "0" ]]; then
  eprint "Expected dynamic metadata to record enabled=True and exit_code=0"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DYNAMIC_COMMAND='bash -lc "exit 9"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-fail) >/dev/null 2>"$tmpdir/stderr-dynamic-fail"
code_dynamic_fail=$?
set -e
if [[ "$code_dynamic_fail" -eq 0 ]]; then
  eprint "Expected dynamic failure run to block"
  exit 1
fi
dynamic_fail_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-fail/test-review.json"
status_dynamic_fail="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$dynamic_fail_json")"
if [[ "$status_dynamic_fail" != "Blocked" ]]; then
  eprint "Expected Blocked status for dynamic failure, got: $status_dynamic_fail"
  exit 1
fi
dynamic_fail_title="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1],encoding="utf-8")).get("findings") or [{}])[0].get("title",""))' "$dynamic_fail_json")"
if [[ "$dynamic_fail_title" != "Dynamic validation failed" ]]; then
  eprint "Expected Dynamic validation failed finding title, got: $dynamic_fail_title"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 3"' TEST_REVIEW_DYNAMIC_COMMAND='bash -lc "echo ran > dynamic-ran.txt; exit 9"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-preflight-fail-with-dynamic) >/dev/null 2>"$tmpdir/stderr-preflight-fail-with-dynamic"
code_preflight_fail_with_dynamic=$?
set -e
if [[ "$code_preflight_fail_with_dynamic" -eq 0 ]]; then
  eprint "Expected preflight failure with dynamic configured to block"
  exit 1
fi
preflight_fail_with_dynamic_json="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-preflight-fail-with-dynamic/test-review.json"
preflight_fail_with_dynamic_meta="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-preflight-fail-with-dynamic/test-review-metadata.json"
preflight_fail_with_dynamic_title="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1],encoding="utf-8")).get("findings") or [{}])[0].get("title",""))' "$preflight_fail_with_dynamic_json")"
if [[ "$preflight_fail_with_dynamic_title" != "Preflight failed" ]]; then
  eprint "Expected Preflight failed finding when preflight fails first, got: $preflight_fail_with_dynamic_title"
  exit 1
fi
preflight_dynamic_exit_code="$(python3 -c 'import json,sys;v=json.load(open(sys.argv[1],encoding="utf-8")).get("dynamic_command_exit_code");print("None" if v is None else v)' "$preflight_fail_with_dynamic_meta")"
if [[ "$preflight_dynamic_exit_code" != "None" ]]; then
  eprint "Expected dynamic_command_exit_code to remain None when preflight fails first"
  exit 1
fi
if [[ -f "$tmpdir/dynamic-ran.txt" ]]; then
  eprint "Dynamic command must not run when preflight fails"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DYNAMIC_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-stale-disabled) >/dev/null 2>"$tmpdir/stderr-dynamic-stale-disabled-create"
code_dynamic_stale_disabled_create=$?
set -e
if [[ "$code_dynamic_stale_disabled_create" -ne 0 ]]; then
  eprint "Expected stale-disabled setup run to succeed"
  cat "$tmpdir/stderr-dynamic-stale-disabled-create" >&2
  exit 1
fi
dynamic_stale_disabled_path="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-stale-disabled/dynamic.txt"
if [[ ! -f "$dynamic_stale_disabled_path" ]]; then
  eprint "Expected dynamic.txt to exist after stale-disabled setup run"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-stale-disabled) >/dev/null 2>"$tmpdir/stderr-dynamic-stale-disabled-rerun"
code_dynamic_stale_disabled_rerun=$?
set -e
if [[ "$code_dynamic_stale_disabled_rerun" -ne 0 ]]; then
  eprint "Expected stale-disabled rerun without dynamic command to succeed"
  cat "$tmpdir/stderr-dynamic-stale-disabled-rerun" >&2
  exit 1
fi
if [[ -f "$dynamic_stale_disabled_path" ]]; then
  eprint "Expected stale dynamic.txt to be removed when dynamic command is disabled"
  exit 1
fi
dynamic_stale_disabled_meta="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-stale-disabled/test-review-metadata.json"
dynamic_stale_disabled_enabled="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("dynamic_command_enabled"))' "$dynamic_stale_disabled_meta")"
dynamic_stale_disabled_exit_code="$(python3 -c 'import json,sys;v=json.load(open(sys.argv[1],encoding="utf-8")).get("dynamic_command_exit_code");print("None" if v is None else v)' "$dynamic_stale_disabled_meta")"
if [[ "$dynamic_stale_disabled_enabled" != "False" || "$dynamic_stale_disabled_exit_code" != "None" ]]; then
  eprint "Expected disabled dynamic metadata after stale-disabled rerun"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DYNAMIC_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-stale-preflight) >/dev/null 2>"$tmpdir/stderr-dynamic-stale-preflight-create"
code_dynamic_stale_preflight_create=$?
set -e
if [[ "$code_dynamic_stale_preflight_create" -ne 0 ]]; then
  eprint "Expected stale-preflight setup run to succeed"
  cat "$tmpdir/stderr-dynamic-stale-preflight-create" >&2
  exit 1
fi
dynamic_stale_preflight_path="$tmpdir/.agentic-sdd/test-reviews/issue-1/run-dynamic-stale-preflight/dynamic.txt"
if [[ ! -f "$dynamic_stale_preflight_path" ]]; then
  eprint "Expected dynamic.txt to exist after stale-preflight setup run"
  exit 1
fi

set +e
(cd "$tmpdir" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 3"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-dynamic-stale-preflight) >/dev/null 2>"$tmpdir/stderr-dynamic-stale-preflight-rerun"
code_dynamic_stale_preflight_rerun=$?
set -e
if [[ "$code_dynamic_stale_preflight_rerun" -eq 0 ]]; then
  eprint "Expected stale-preflight rerun to fail because preflight fails"
  exit 1
fi
if [[ -f "$dynamic_stale_preflight_path" ]]; then
  eprint "Expected stale dynamic.txt to be removed when preflight fails"
  exit 1
fi

tmpdir_root_js="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-test-review-root-js)"
cleanup_root_js() { rm -rf "$tmpdir_root_js"; }
trap 'cleanup_root_js; cleanup' EXIT

git -C "$tmpdir_root_js" init -q
cat > "$tmpdir_root_js/hello.sh" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
cat > "$tmpdir_root_js/root.spec.ts" <<'EOF'
describe('root level test', () => {
  it('passes', () => {})
})
EOF
cat > "$tmpdir_root_js/root.spec.unit.ts" <<'EOF'
describe('root level test', () => {
  it('passes', () => {})
})
EOF
cat > "$tmpdir_root_js/root.spec.e2e.browser.ts" <<'EOF'
describe('root level test', () => {
  it('passes', () => {})
})
EOF
git -C "$tmpdir_root_js" add hello.sh root.spec.ts root.spec.unit.ts root.spec.e2e.browser.ts
git -C "$tmpdir_root_js" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir_root_js" branch -M main

echo "code-change" >> "$tmpdir_root_js/hello.sh"
echo "// tweak" >> "$tmpdir_root_js/root.spec.ts"
echo "// tweak" >> "$tmpdir_root_js/root.spec.unit.ts"
echo "// tweak" >> "$tmpdir_root_js/root.spec.e2e.browser.ts"
git -C "$tmpdir_root_js" add hello.sh root.spec.ts root.spec.unit.ts root.spec.e2e.browser.ts

set +e
(cd "$tmpdir_root_js" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-root-level-js-tests) >/dev/null 2>"$tmpdir_root_js/stderr-root-js"
code_root_js=$?
set -e
if [[ "$code_root_js" -ne 0 ]]; then
  eprint "Expected root-level JS/TS test changes to satisfy test update gate"
  cat "$tmpdir_root_js/stderr-root-js" >&2
  exit 1
fi

root_js_json="$tmpdir_root_js/.agentic-sdd/test-reviews/issue-1/run-root-level-js-tests/test-review.json"
status_root_js="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$root_js_json")"
if [[ "$status_root_js" != "Approved" ]]; then
  eprint "Expected Approved status for root-level JS/TS tests, got: $status_root_js"
  exit 1
fi

tmpdir_root_non_test="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-test-review-root-non-test)"
cleanup_root_non_test() { rm -rf "$tmpdir_root_non_test"; }
trap 'cleanup_root_non_test; cleanup_root_js; cleanup' EXIT

git -C "$tmpdir_root_non_test" init -q
cat > "$tmpdir_root_non_test/hello.sh" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
cat > "$tmpdir_root_non_test/notes.test.md" <<'EOF'
this is not an executable test file
EOF
cat > "$tmpdir_root_non_test/openapi.spec.yaml" <<'EOF'
openapi: 3.1.0
EOF
git -C "$tmpdir_root_non_test" add hello.sh notes.test.md openapi.spec.yaml
git -C "$tmpdir_root_non_test" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir_root_non_test" branch -M main

echo "code-change" >> "$tmpdir_root_non_test/hello.sh"
echo "note-change" >> "$tmpdir_root_non_test/notes.test.md"
echo "yaml-change" >> "$tmpdir_root_non_test/openapi.spec.yaml"
git -C "$tmpdir_root_non_test" add hello.sh notes.test.md openapi.spec.yaml

set +e
(cd "$tmpdir_root_non_test" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=staged "$script_src" issue-1 run-root-level-non-test-file) >/dev/null 2>"$tmpdir_root_non_test/stderr-root-non-test"
code_root_non_test=$?
set -e
if [[ "$code_root_non_test" -eq 0 ]]; then
  eprint "Expected root-level non-test file pattern not to satisfy test update gate"
  exit 1
fi

root_non_test_json="$tmpdir_root_non_test/.agentic-sdd/test-reviews/issue-1/run-root-level-non-test-file/test-review.json"
status_root_non_test="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$root_non_test_json")"
if [[ "$status_root_non_test" != "Blocked" ]]; then
  eprint "Expected Blocked status for root-level non-test file pattern, got: $status_root_non_test"
  exit 1
fi

tmpdir_untracked_auto="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-test-review-untracked-auto)"
cleanup_untracked_auto() { rm -rf "$tmpdir_untracked_auto"; }
trap 'cleanup_untracked_auto; cleanup_root_non_test; cleanup_root_js; cleanup' EXIT

git -C "$tmpdir_untracked_auto" init -q
cat > "$tmpdir_untracked_auto/hello.sh" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
git -C "$tmpdir_untracked_auto" add hello.sh
git -C "$tmpdir_untracked_auto" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir_untracked_auto" branch -M main

cat > "$tmpdir_untracked_auto/new-feature.sh" <<'EOF'
#!/usr/bin/env bash
echo feature
EOF
mkdir -p "$tmpdir_untracked_auto/scripts/tests"
cat > "$tmpdir_untracked_auto/scripts/tests/test-new-feature.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ 1 -eq 1 ]]
EOF

set +e
(cd "$tmpdir_untracked_auto" && TEST_REVIEW_PREFLIGHT_COMMAND='bash -lc "exit 0"' TEST_REVIEW_DIFF_MODE=auto "$script_src" issue-1 run-untracked-auto) >/dev/null 2>"$tmpdir_untracked_auto/stderr-untracked-auto"
code_untracked_auto=$?
set -e
if [[ "$code_untracked_auto" -ne 0 ]]; then
  eprint "Expected auto mode to include untracked files"
  cat "$tmpdir_untracked_auto/stderr-untracked-auto" >&2
  exit 1
fi

untracked_auto_json="$tmpdir_untracked_auto/.agentic-sdd/test-reviews/issue-1/run-untracked-auto/test-review.json"
status_untracked_auto="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$untracked_auto_json")"
if [[ "$status_untracked_auto" != "Approved" ]]; then
  eprint "Expected Approved status for untracked auto mode case, got: $status_untracked_auto"
  exit 1
fi

eprint "OK: scripts/tests/test-test-review.sh"
