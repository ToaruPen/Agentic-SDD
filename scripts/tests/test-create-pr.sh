#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_src="$repo_root/scripts/shell/create-pr.sh"

if [[ ! -x "$script_src" ]]; then
	eprint "Missing script or not executable: $script_src"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-create-pr-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

origin_bare="$tmpdir/origin.git"
git init -q --bare "$origin_bare"

work="$tmpdir/work"
mkdir -p "$work"
git -C "$work" init -q
git -C "$work" remote add origin "$origin_bare"

cat >"$work/README.md" <<'EOF'
# Temp Repo
EOF

git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$work" branch -M main
git -C "$work" push -u origin main -q

git -C "$work" checkout -b feature/issue-1-test -q
echo "change" >>"$work/README.md"
git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "feat: change" -q

# review-cycle fixture
mkdir -p "$work/.agentic-sdd/reviews/issue-1/run1"
printf '%s' 'run1' >"$work/.agentic-sdd/reviews/issue-1/.current_run"
cat >"$work/.agentic-sdd/reviews/issue-1/run1/review.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "ok"
}
EOF

mkdir -p "$work/.agentic-sdd/test-reviews/issue-1/run1"
printf '%s' 'run1' >"$work/.agentic-sdd/test-reviews/issue-1/.current_run"
cat >"$work/.agentic-sdd/test-reviews/issue-1/run1/test-review.json" <<'EOF'
{
  "schema_version": 1,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "overall_explanation": "ok"
}
EOF

write_review_metadata() {
	local head_sha="$1"
	local base_ref="$2"
	local base_sha="$3"
	local diff_source="${4:-range}"
	cat >"$work/.agentic-sdd/reviews/issue-1/run1/review-metadata.json" <<EOF
{
  "schema_version": 1,
  "scope_id": "issue-1",
  "run_id": "run1",
  "diff_source": "${diff_source}",
  "base_ref": "${base_ref}",
  "base_sha": "${base_sha}",
  "head_sha": "${head_sha}",
  "diff_sha256": "stub"
}
EOF
}

write_test_review_metadata() {
	local head_sha="$1"
	local base_ref="$2"
	local base_sha="$3"
	local diff_mode="${4:-range}"
	cat >"$work/.agentic-sdd/test-reviews/issue-1/run1/test-review-metadata.json" <<EOF
{
  "schema_version": 1,
  "scope_id": "issue-1",
  "run_id": "run1",
  "head_sha": "${head_sha}",
  "base_ref": "${base_ref}",
  "base_sha": "${base_sha}",
  "diff_mode": "${diff_mode}"
}
EOF
}

setup_decision_fixtures() {
	mkdir -p "$work/scripts/gates" "$work/docs/decisions"
	cp "$repo_root/scripts/gates/validate_decision_index.py" "$work/scripts/gates/validate_decision_index.py"
	cat >"$work/docs/decisions/_template.md" <<'TMPL'
## Decision-ID

## Context

## Rationale

## Alternatives

## Impact

## Verification

## Supersedes

## Inputs Fingerprint
TMPL

	cat >"$work/docs/decisions.md" <<'IDX'
# Decisions

## Decision Index
IDX
}

setup_worktree_check_stub() {
	mkdir -p "$work/scripts/agentic-sdd"
	cat >"$work/scripts/agentic-sdd/worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "check" ]]; then
	echo "unsupported worktree invocation" >&2
	exit 2
fi

shift
dup_issue=0
seen_issues=" "
while [[ "$#" -gt 0 ]]; do
	if [[ "${1:-}" != "--issue" ]]; then
		echo "invalid worktree check args" >&2
		exit 2
	fi
	issue="${2:-}"
	if [[ -z "$issue" ]]; then
		echo "missing issue value" >&2
		exit 2
	fi
	if [[ "$seen_issues" == *" $issue "* ]]; then
		dup_issue=1
	else
		seen_issues+="$issue "
	fi
	shift 2
done

if [[ "${AGENTIC_SDD_TEST_WORKTREE_FAIL_ON_DUPLICATE:-0}" == "1" && "$dup_issue" -eq 1 ]]; then
	echo "duplicate issue id" >&2
	exit 9
fi

case "${AGENTIC_SDD_TEST_WORKTREE_CHECK_EXIT:-0}" in
	0)
		echo "OK: no overlaps"
		exit 0
		;;
	3)
		echo "CONFLICT: issue:1 <-> issue:2" >&2
		echo "Overlapping files:" >&2
		echo "README.md" >&2
		exit 3
		;;
	*)
		echo "stub worktree check failed" >&2
		exit "${AGENTIC_SDD_TEST_WORKTREE_CHECK_EXIT:-1}"
		;;
esac
EOF
	chmod +x "$work/scripts/agentic-sdd/worktree.sh"
}

setup_repo_worktree_check_stub() {
	mkdir -p "$work/scripts/shell"
	cat >"$work/scripts/shell/worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "repo-level worktree stub invoked" >&2
exit "${AGENTIC_SDD_TEST_REPO_WORKTREE_EXIT:-9}"
EOF
	chmod +x "$work/scripts/shell/worktree.sh"
}

base_sha="$(git -C "$work" rev-parse origin/main)"
head_sha="$(git -C "$work" rev-parse HEAD)"
write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "origin/main" "$base_sha"
setup_decision_fixtures
setup_worktree_check_stub

mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$tmpdir/bin/gh"

rm -f "$work/.agentic-sdd/test-reviews/issue-1/.current_run"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_missing_test_review"
code_missing_test_review=$?
set -e
if [[ "$code_missing_test_review" -eq 0 ]]; then
	eprint "Expected missing test-review output to fail"
	exit 1
fi
if ! grep -q "Missing /test-review output" "$tmpdir/stderr_missing_test_review"; then
	eprint "Expected missing test-review error message, got:"
	cat "$tmpdir/stderr_missing_test_review" >&2
	exit 1
fi

printf '%s' '../issue-2/run1' >"$work/.agentic-sdd/test-reviews/issue-1/.current_run"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_invalid_test_review_run_id"
code_invalid_test_review_run_id=$?
set -e
if [[ "$code_invalid_test_review_run_id" -eq 0 ]]; then
	eprint "Expected unsafe test-review run id to fail"
	exit 1
fi
if ! grep -q "Invalid test-review .current_run (unsafe run id)" "$tmpdir/stderr_invalid_test_review_run_id"; then
	eprint "Expected unsafe test-review run id error message, got:"
	cat "$tmpdir/stderr_invalid_test_review_run_id" >&2
	exit 1
fi

printf '%s' 'run1' >"$work/.agentic-sdd/test-reviews/issue-1/.current_run"

# Stub gh (no network/auth)
mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="$(dirname "$0")"
pr_state="$state_dir/pr_state"

if [[ ${1:-} == "auth" && ${2:-} == "status" ]]; then
  exit 0
fi

if [[ ${1:-} == "issue" && ${2:-} == "develop" && ${3:-} == "--list" ]]; then
  issue="${4:-}"
  if [[ "$issue" == "1" ]]; then
    printf '%b\n' "feature/issue-1-test\thttps://example.invalid/tree/feature/issue-1-test"
    exit 0
  fi
  exit 0
fi

if [[ ${1:-} == "issue" && ${2:-} == "view" ]]; then
  issue="${3:-}"
  # We ignore --json args in this stub.
  if [[ "$issue" == "1" ]]; then
    printf '{"title":"Issue 1 title","url":"https://example.invalid/issues/1"}\n'
    exit 0
  fi
  printf '{"title":"Issue %s"}\n' "$issue"
  exit 0
fi

if [[ ${1:-} == "pr" && ${2:-} == "list" ]]; then
  # gh pr list --head <branch> --state all --json ...
  if [[ -f "$pr_state" ]]; then
    cat "$pr_state"
  else
    printf '[]\n'
  fi
  exit 0
fi

if [[ ${1:-} == "pr" && ${2:-} == "create" ]]; then
  # Return URL and persist state
  url="https://example.invalid/pull/1"
  printf '[{"number":1,"url":"%s","state":"OPEN"}]\n' "$url" > "$pr_state"
  printf '%s\n' "$url"
  exit 0
fi

echo "unsupported gh invocation" >&2
exit 2
EOF
chmod +x "$tmpdir/bin/gh"

# Stale head should fail and require re-review.
echo "next" >>"$work/README.md"
git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "feat: next" -q
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_stale_head"
code_stale_head=$?
set -e
if [[ "$code_stale_head" -eq 0 ]]; then
	eprint "Expected stale reviewed HEAD to fail"
	exit 1
fi
if ! grep -q "Current HEAD differs from reviewed HEAD" "$tmpdir/stderr_stale_head"; then
	eprint "Expected stale HEAD error message, got:"
	cat "$tmpdir/stderr_stale_head" >&2
	exit 1
fi

set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" AGENTIC_SDD_PARALLEL_ISSUES='2,abc' "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_parallel_invalid"
code_parallel_invalid=$?
set -e
if [[ "$code_parallel_invalid" -eq 0 ]]; then
	eprint "Expected invalid AGENTIC_SDD_PARALLEL_ISSUES to fail"
	exit 1
fi
if ! grep -q "Invalid AGENTIC_SDD_PARALLEL_ISSUES entry" "$tmpdir/stderr_parallel_invalid"; then
	eprint "Expected invalid parallel issues error message, got:"
	cat "$tmpdir/stderr_parallel_invalid" >&2
	exit 1
fi

set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" AGENTIC_SDD_PARALLEL_ISSUES='2' AGENTIC_SDD_TEST_WORKTREE_CHECK_EXIT=3 "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_parallel_overlap"
code_parallel_overlap=$?
set -e
if [[ "$code_parallel_overlap" -eq 0 ]]; then
	eprint "Expected parallel integration overlap to fail"
	exit 1
fi
if ! grep -q "Parallel integration conflict detected by worktree check" "$tmpdir/stderr_parallel_overlap"; then
	eprint "Expected parallel overlap error message, got:"
	cat "$tmpdir/stderr_parallel_overlap" >&2
	exit 1
fi

# Refresh metadata for current head.
head_sha="$(git -C "$work" rev-parse HEAD)"
write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "origin/main" "$base_sha"

(cd "$work" && PATH="$tmpdir/bin:$PATH" AGENTIC_SDD_PARALLEL_ISSUES='2' "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null

setup_repo_worktree_check_stub
(cd "$work" && PATH="$tmpdir/bin:$PATH" AGENTIC_SDD_PARALLEL_ISSUES='2' AGENTIC_SDD_TEST_REPO_WORKTREE_EXIT=9 "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null

set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" AGENTIC_SDD_PARALLEL_ISSUES='2,2' AGENTIC_SDD_TEST_WORKTREE_FAIL_ON_DUPLICATE=1 "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_parallel_duplicate"
code_parallel_duplicate=$?
set -e
if [[ "$code_parallel_duplicate" -ne 0 ]]; then
	eprint "Expected duplicate AGENTIC_SDD_PARALLEL_ISSUES entries to be deduplicated"
	cat "$tmpdir/stderr_parallel_duplicate" >&2
	exit 1
fi

# Stale base should fail and require re-review.
git -C "$work" checkout main -q
echo "main-update" >>"$work/README.md"
git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "chore: main update" -q
git -C "$work" push origin main -q
# Simulate a stale local remote-tracking ref. The script should fetch before comparing.
git -C "$work" update-ref refs/remotes/origin/main "$base_sha"
git -C "$work" checkout feature/issue-1-test -q
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_stale_base"
code_stale_base=$?
set -e
if [[ "$code_stale_base" -eq 0 ]]; then
	eprint "Expected moved base ref to fail"
	exit 1
fi
if ! grep -q "Base ref 'origin/main' moved since /test-review" "$tmpdir/stderr_stale_base"; then
	eprint "Expected stale base error message, got:"
	cat "$tmpdir/stderr_stale_base" >&2
	exit 1
fi

# Refresh metadata after base/head drift fixes.
base_sha="$(git -C "$work" rev-parse origin/main)"
head_sha="$(git -C "$work" rev-parse HEAD)"
write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "origin/main" "$base_sha"

# Local base branch names that include "/" must not be treated as remote refs,
# even when a same-prefix remote exists.
release_bare="$tmpdir/release.git"
git init -q --bare "$release_bare"
git -C "$work" remote add release "$release_bare"
git -C "$work" branch release/v1 "$base_sha"
release_base_sha="$(git -C "$work" rev-parse release/v1)"
git -C "$work" update-ref refs/remotes/release/v1 "$release_base_sha"
write_review_metadata "$head_sha" "release/v1" "$release_base_sha"
write_test_review_metadata "$head_sha" "release/v1" "$release_base_sha"
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base release/v1) >/dev/null 2>"$tmpdir/stderr_local_slash_base"

# Restore metadata for origin/main scenarios below.
write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "origin/main" "$base_sha"
git -C "$work" branch develop "$base_sha"
develop_sha="$(git -C "$work" rev-parse develop)"

# PR base override must match reviewed base branch.
write_test_review_metadata "$head_sha" "develop" "$develop_sha"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base develop) >/dev/null 2>"$tmpdir/stderr_base_branch_mismatch"
code_base_branch_mismatch=$?
set -e
if [[ "$code_base_branch_mismatch" -eq 0 ]]; then
	eprint "Expected reviewed base branch mismatch to fail"
	exit 1
fi
if ! grep -q "PR base 'develop' differs from reviewed base 'main'" "$tmpdir/stderr_base_branch_mismatch"; then
	eprint "Expected base branch mismatch error message, got:"
	cat "$tmpdir/stderr_base_branch_mismatch" >&2
	exit 1
fi

write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "develop" "$develop_sha"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_test_base_branch_mismatch"
code_test_base_branch_mismatch=$?
set -e
if [[ "$code_test_base_branch_mismatch" -eq 0 ]]; then
	eprint "Expected test-reviewed base branch mismatch to fail"
	exit 1
fi
if ! grep -q "PR base 'main' differs from test-reviewed base 'develop'" "$tmpdir/stderr_test_base_branch_mismatch"; then
	eprint "Expected test-reviewed base branch mismatch error message, got:"
	cat "$tmpdir/stderr_test_base_branch_mismatch" >&2
	exit 1
fi

write_test_review_metadata "$head_sha" "develop" "$develop_sha" "worktree"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_test_worktree_diff_mode"
code_test_worktree_diff_mode=$?
set -e
if [[ "$code_test_worktree_diff_mode" -eq 0 ]]; then
	eprint "Expected non-range test-review diff_mode to fail"
	exit 1
fi
if ! grep -q "diff_mode must be 'range'" "$tmpdir/stderr_test_worktree_diff_mode"; then
	eprint "Expected non-range test-review diff_mode error message, got:"
	cat "$tmpdir/stderr_test_worktree_diff_mode" >&2
	exit 1
fi

write_test_review_metadata "$head_sha" "origin/main" "$base_sha" "unknown"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_test_invalid_diff_mode"
code_test_invalid_diff_mode=$?
set -e
if [[ "$code_test_invalid_diff_mode" -eq 0 ]]; then
	eprint "Expected invalid test-review diff_mode to fail"
	exit 1
fi
if ! grep -q "diff_mode must be 'range'" "$tmpdir/stderr_test_invalid_diff_mode"; then
	eprint "Expected invalid test-review diff_mode error message, got:"
	cat "$tmpdir/stderr_test_invalid_diff_mode" >&2
	exit 1
fi

write_test_review_metadata "$head_sha" "origin/main" "" "range"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_test_range_missing_base_sha"
code_test_range_missing_base_sha=$?
set -e
if [[ "$code_test_range_missing_base_sha" -eq 0 ]]; then
	eprint "Expected missing test-review base_sha for range mode to fail"
	exit 1
fi
if ! grep -q "Invalid test-review metadata (diff_mode=range requires base_sha)" "$tmpdir/stderr_test_range_missing_base_sha"; then
	eprint "Expected missing test-review base_sha error message, got:"
	cat "$tmpdir/stderr_test_range_missing_base_sha" >&2
	exit 1
fi

write_test_review_metadata "$head_sha" "origin/main" "$base_sha"
write_review_metadata "$head_sha" "origin/main" "$base_sha" "staged"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_review_diff_source_not_range"
code_review_diff_source_not_range=$?
set -e
if [[ "$code_review_diff_source_not_range" -eq 0 ]]; then
	eprint "Expected non-range review diff_source to fail"
	exit 1
fi
if ! grep -q "diff_source must be 'range'" "$tmpdir/stderr_review_diff_source_not_range"; then
	eprint "Expected non-range review diff_source error message, got:"
	cat "$tmpdir/stderr_review_diff_source_not_range" >&2
	exit 1
fi

write_review_metadata "$head_sha" "origin/main" "" "range"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1 --base main) >/dev/null 2>"$tmpdir/stderr_review_range_missing_base_sha"
code_review_range_missing_base_sha=$?
set -e
if [[ "$code_review_range_missing_base_sha" -eq 0 ]]; then
	eprint "Expected missing review base_sha for range diff_source to fail"
	exit 1
fi
if ! grep -q "Invalid review metadata (diff_source=range requires base_sha)" "$tmpdir/stderr_review_range_missing_base_sha"; then
	eprint "Expected missing review base_sha error message, got:"
	cat "$tmpdir/stderr_review_range_missing_base_sha" >&2
	exit 1
fi

write_review_metadata "$head_sha" "origin/main" "$base_sha" "range"

(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null

out="$(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --issue 1 2>/dev/null)"
if [[ "$out" != "https://example.invalid/pull/1" ]]; then
	eprint "Expected PR URL, got: $out"
	exit 1
fi

# Second run should reuse existing PR (same URL)
out2="$(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --issue 1 2>/dev/null)"
if [[ "$out2" != "https://example.invalid/pull/1" ]]; then
	eprint "Expected existing PR URL, got: $out2"
	exit 1
fi

# --- Decision Index validation gate tests ---

# Reset PR state so gh stub creates fresh
rm -f "$tmpdir/bin/pr_state"

setup_decision_fixtures

# Refresh metadata for current head (required after prior test mutations)
head_sha="$(git -C "$work" rev-parse HEAD)"
base_sha="$(git -C "$work" rev-parse origin/main)"
write_review_metadata "$head_sha" "origin/main" "$base_sha"
write_test_review_metadata "$head_sha" "origin/main" "$base_sha"

rm -f "$work/scripts/gates/validate_decision_index.py"
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_decision_validator_missing"
code_decision_validator_missing=$?
set -e
if [[ "$code_decision_validator_missing" -eq 0 ]]; then
	eprint "Expected missing decision validator to fail create-pr"
	exit 1
fi
if ! grep -q "Missing decision validator" "$tmpdir/stderr_decision_validator_missing"; then
	eprint "Expected missing decision validator message, got:"
	cat "$tmpdir/stderr_decision_validator_missing" >&2
	exit 1
fi

setup_decision_fixtures

# Decision validation should pass (no body files, no index entries = valid empty state)
set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null
code_decision_empty_valid=$?
set -e
if [[ "$code_decision_empty_valid" -ne 0 ]]; then
	eprint "Expected empty decision state to pass create-pr"
	exit 1
fi

# Now create an orphan body file (no matching index entry) -> should fail
cat >"$work/docs/decisions/d-2026-01-01-test-orphan.md" <<'BODY'
## Decision-ID

D-2026-01-01-TEST_ORPHAN

## Context

Test context

## Rationale

Test rationale

## Alternatives

None

## Impact

None

## Verification

Manual

## Supersedes

- N/A

## Inputs Fingerprint

N/A
BODY

set +e
(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>"$tmpdir/stderr_decision_orphan"
code_decision_orphan=$?
set -e
if [[ "$code_decision_orphan" -eq 0 ]]; then
	eprint "Expected orphan decision body to fail create-pr"
	exit 1
fi
if ! grep -q "Decision Index validation failed" "$tmpdir/stderr_decision_orphan"; then
	eprint "Expected Decision Index validation failed message, got:"
	cat "$tmpdir/stderr_decision_orphan" >&2
	exit 1
fi

# Fix by adding the entry to the index -> should pass
cat >"$work/docs/decisions.md" <<'IDX'
# Decisions

## Decision Index

- D-2026-01-01-TEST_ORPHAN: [`d-2026-01-01-test-orphan.md`](./decisions/d-2026-01-01-test-orphan.md)
IDX

(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null

rm -rf "$work/docs/decisions" "$work/docs/decisions.md" "$work/scripts/gates/validate_decision_index.py"

eprint "OK: scripts/tests/test-create-pr.sh"
