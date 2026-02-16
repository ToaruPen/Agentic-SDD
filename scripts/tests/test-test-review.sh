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
git -C "$tmpdir" add hello.sh
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir" branch -M main

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

mkdir -p "$tmpdir/scripts/tests"
cat > "$tmpdir/scripts/tests/test-sample.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ 1 -eq 1 ]]
EOF
chmod +x "$tmpdir/scripts/tests/test-sample.sh"
git -C "$tmpdir" add hello.sh scripts/tests/test-sample.sh

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

eprint "OK: scripts/tests/test-test-review.sh"
