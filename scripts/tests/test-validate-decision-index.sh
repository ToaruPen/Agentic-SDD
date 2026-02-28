#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
validate_py="$repo_root/scripts/validate-decision-index.py"

if [[ ! -f "$validate_py" ]]; then
	eprint "Missing validation script: $validate_py"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-decision-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

new_repo() {
	local name="$1"
	local r="$tmpdir/$name"
	mkdir -p "$r"
	git -C "$r" init -q
	mkdir -p "$r/docs/decisions" "$r/scripts"
	cp -p "$validate_py" "$r/scripts/validate-decision-index.py"
	chmod +x "$r/scripts/validate-decision-index.py"
	printf '%s\n' "$r"
}

# --- Helper: write a valid decision body file ---
write_valid_decision() {
	local dir="$1" id="$2" fname="$3"
	cat >"$dir/docs/decisions/$fname" <<EOF
# Decision: Test Decision

## Decision-ID

$id

## Context

- 背景: test

## Rationale

- reason

## Alternatives

### Alternative-A: none

- 採用可否: No

## Impact

- 影響: none

## Verification

- 検証方法: test

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: N/A
EOF
}

# --- Helper: write template ---
write_template() {
	local dir="$1"
	cat >"$dir/docs/decisions/_template.md" <<'EOF'
# Decision: <short-title>

## Decision-ID

D-YYYY-MM-DD-SHORT_KEBAB

## Context

- 背景:

## Rationale

- reason

## Alternatives

### Alternative-A: <name>

- 採用可否:

## Impact

- 影響範囲:

## Verification

- 検証方法:

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: <path:section>
EOF
}

# --- Helper: write a valid index ---
write_valid_index() {
	local dir="$1"
	shift
	{
		cat <<'HEADER'
# 意思決定ログ（Decision Snapshot）

## Decision Index

HEADER
		for entry in "$@"; do
			printf '%s\n' "$entry"
		done
	} >"$dir/docs/decisions.md"
}

passed=0
failed=0

run_test() {
	local desc="$1"
	shift
	if "$@"; then
		passed=$((passed + 1))
	else
		eprint "FAIL: $desc"
		failed=$((failed + 1))
	fi
}

# ===========================================================================
# AC1: Template required fields validation
# ===========================================================================

# Case 1: Valid decision body file — should pass
eprint "--- AC1: case-valid-body ---"
r1="$(new_repo case-valid-body)"
write_template "$r1"
write_valid_decision "$r1" "D-2026-02-28-TEST" "d-2026-02-28-test.md"
write_valid_index "$r1" "- D-2026-02-28-TEST: [\`docs/decisions/d-2026-02-28-test.md\`](./decisions/d-2026-02-28-test.md)"
run_test "AC1: valid body passes" bash -c "(cd '$r1' && python3 ./scripts/validate-decision-index.py)"

# Case 2: Missing required field (no Rationale section) — should fail
eprint "--- AC1: case-missing-field ---"
r2="$(new_repo case-missing-field)"
write_template "$r2"
cat >"$r2/docs/decisions/d-2026-02-28-bad.md" <<'EOF'
# Decision: Bad

## Decision-ID

D-2026-02-28-BAD

## Context

- 背景: test

## Alternatives

### Alternative-A: none

## Impact

- 影響: none

## Verification

- 検証方法: test

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r2" "- D-2026-02-28-BAD: [\`docs/decisions/d-2026-02-28-bad.md\`](./decisions/d-2026-02-28-bad.md)"

set +e
(cd "$r2" && python3 ./scripts/validate-decision-index.py) >"$r2/stdout" 2>"$r2/stderr"
code_ac1_missing=$?
set -e

run_test "AC1: missing field fails (exit!=0)" test "$code_ac1_missing" -ne 0
run_test "AC1: error mentions Rationale" grep -q "Rationale" "$r2/stderr"

# ===========================================================================
# AC2: Index <-> body correspondence (missing, duplicate, invalid ref)
# ===========================================================================

# Case 3: Body file exists but not in index — should fail
eprint "--- AC2: case-body-not-in-index ---"
r3="$(new_repo case-body-not-in-index)"
write_template "$r3"
write_valid_decision "$r3" "D-2026-02-28-ORPHAN" "d-2026-02-28-orphan.md"
write_valid_index "$r3" # empty index
set +e
(cd "$r3" && python3 ./scripts/validate-decision-index.py) >"$r3/stdout" 2>"$r3/stderr"
code_ac2_orphan=$?
set -e

run_test "AC2: orphan body fails (exit!=0)" test "$code_ac2_orphan" -ne 0
run_test "AC2: error mentions orphan file" grep -q "d-2026-02-28-orphan.md" "$r3/stderr"

# Case 4: Index references a file that doesn't exist — should fail
eprint "--- AC2: case-dangling-index ---"
r4="$(new_repo case-dangling-index)"
write_template "$r4"
write_valid_index "$r4" "- D-2026-02-28-GHOST: [\`docs/decisions/d-2026-02-28-ghost.md\`](./decisions/d-2026-02-28-ghost.md)"
set +e
(cd "$r4" && python3 ./scripts/validate-decision-index.py) >"$r4/stdout" 2>"$r4/stderr"
code_ac2_dangling=$?
set -e

run_test "AC2: dangling index ref fails (exit!=0)" test "$code_ac2_dangling" -ne 0
run_test "AC2: error mentions missing file" grep -q "d-2026-02-28-ghost.md" "$r4/stderr"

# Case 5: Duplicate index entry — should fail
eprint "--- AC2: case-duplicate-index ---"
r5="$(new_repo case-duplicate-index)"
write_template "$r5"
write_valid_decision "$r5" "D-2026-02-28-DUP" "d-2026-02-28-dup.md"
write_valid_index "$r5" \
	"- D-2026-02-28-DUP: [\`docs/decisions/d-2026-02-28-dup.md\`](./decisions/d-2026-02-28-dup.md)" \
	"- D-2026-02-28-DUP: [\`docs/decisions/d-2026-02-28-dup.md\`](./decisions/d-2026-02-28-dup.md)"
set +e
(cd "$r5" && python3 ./scripts/validate-decision-index.py) >"$r5/stdout" 2>"$r5/stderr"
code_ac2_dup=$?
set -e

run_test "AC2: duplicate index fails (exit!=0)" test "$code_ac2_dup" -ne 0
run_test "AC2: error mentions duplicate" grep -qi "duplicate\|重複" "$r5/stderr"

eprint "--- AC2: case-index-body-id-mismatch ---"
r5b="$(new_repo case-index-body-id-mismatch)"
write_template "$r5b"
write_valid_decision "$r5b" "D-2026-02-28-REAL" "d-2026-02-28-real.md"
write_valid_index "$r5b" "- D-2026-02-28-WRONG: [\`docs/decisions/d-2026-02-28-real.md\`](./decisions/d-2026-02-28-real.md)"
set +e
(cd "$r5b" && python3 ./scripts/validate-decision-index.py) >"$r5b/stdout" 2>"$r5b/stderr"
code_ac2_mismatch=$?
set -e

run_test "AC2: index/body ID mismatch fails (exit!=0)" test "$code_ac2_mismatch" -ne 0
run_test "AC2: error mentions ID mismatch" grep -q "Index/body Decision-ID mismatch" "$r5b/stderr"

eprint "--- AC2: case-duplicate-body-decision-id ---"
r5c="$(new_repo case-duplicate-body-decision-id)"
write_template "$r5c"
write_valid_decision "$r5c" "D-2026-02-28-DUPBODY" "d-2026-02-28-a.md"
write_valid_decision "$r5c" "D-2026-02-28-DUPBODY" "d-2026-02-28-b.md"
write_valid_index "$r5c" \
	"- D-2026-02-28-DUPBODY: [\`docs/decisions/d-2026-02-28-a.md\`](./decisions/d-2026-02-28-a.md)" \
	"- D-2026-02-28-OTHER: [\`docs/decisions/d-2026-02-28-b.md\`](./decisions/d-2026-02-28-b.md)"
set +e
(cd "$r5c" && python3 ./scripts/validate-decision-index.py) >"$r5c/stdout" 2>"$r5c/stderr"
code_ac2_dup_body=$?
set -e

run_test "AC2: duplicate body Decision-ID fails (exit!=0)" test "$code_ac2_dup_body" -ne 0
run_test "AC2: error mentions duplicate body Decision-ID" grep -q "Duplicate Decision-ID in body files" "$r5c/stderr"

# ===========================================================================
# AC3: Supersedes references point to existing Decision-IDs
# ===========================================================================

# Case 6: Supersedes references a valid existing Decision-ID — should pass
eprint "--- AC3: case-valid-supersedes ---"
r6="$(new_repo case-valid-supersedes)"
write_template "$r6"
write_valid_decision "$r6" "D-2026-02-01-OLD" "d-2026-02-01-old.md"
# New decision that supersedes the old one
cat >"$r6/docs/decisions/d-2026-02-28-new.md" <<'EOF'
# Decision: New Decision

## Decision-ID

D-2026-02-28-NEW

## Context

- 背景: superseding old

## Rationale

- reason

## Alternatives

### Alternative-A: none

- 採用可否: No

## Impact

- 影響: none

## Verification

- 検証方法: test

## Supersedes

- D-2026-02-01-OLD

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r6" \
	"- D-2026-02-01-OLD: [\`docs/decisions/d-2026-02-01-old.md\`](./decisions/d-2026-02-01-old.md)" \
	"- D-2026-02-28-NEW: [\`docs/decisions/d-2026-02-28-new.md\`](./decisions/d-2026-02-28-new.md)"
run_test "AC3: valid supersedes passes" bash -c "(cd '$r6' && python3 ./scripts/validate-decision-index.py)"

# Case 7: Supersedes references a non-existent Decision-ID — should fail
eprint "--- AC3: case-bad-supersedes ---"
r7="$(new_repo case-bad-supersedes)"
write_template "$r7"
cat >"$r7/docs/decisions/d-2026-02-28-broken.md" <<'EOF'
# Decision: Broken Supersedes

## Decision-ID

D-2026-02-28-BROKEN

## Context

- 背景: test

## Rationale

- reason

## Alternatives

### Alternative-A: none

- 採用可否: No

## Impact

- 影響: none

## Verification

- 検証方法: test

## Supersedes

- D-2026-01-01-NONEXISTENT

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r7" "- D-2026-02-28-BROKEN: [\`docs/decisions/d-2026-02-28-broken.md\`](./decisions/d-2026-02-28-broken.md)"
set +e
(cd "$r7" && python3 ./scripts/validate-decision-index.py) >"$r7/stdout" 2>"$r7/stderr"
code_ac3_bad=$?
set -e

run_test "AC3: bad supersedes fails (exit!=0)" test "$code_ac3_bad" -ne 0
run_test "AC3: error mentions nonexistent ID" grep -q "D-2026-01-01-NONEXISTENT" "$r7/stderr"
run_test "AC3: error includes guidance" grep -qi "supersedes\|修正" "$r7/stderr"

# ===========================================================================
# Edge cases
# ===========================================================================

# Case 8: _template.md and README.md should be skipped (not treated as body)
eprint "--- Edge: template and README skipped ---"
r8="$(new_repo case-skip-template)"
write_template "$r8"
cat >"$r8/docs/decisions/README.md" <<'EOF'
# Decision Snapshot 運用ルール
EOF
write_valid_index "$r8" # empty index, no body files
run_test "Edge: template/README not treated as orphan" bash -c "(cd '$r8' && python3 ./scripts/validate-decision-index.py)"

# Case 9: No decisions.md at all — should fail
eprint "--- Edge: case-no-index-file ---"
r9="$(new_repo case-no-index-file)"
write_template "$r9"
rm -f "$r9/docs/decisions.md"
set +e
(cd "$r9" && python3 ./scripts/validate-decision-index.py) >"$r9/stdout" 2>"$r9/stderr"
code_no_index=$?
set -e

run_test "Edge: no decisions.md fails (exit!=0)" test "$code_no_index" -ne 0

# ===========================================================================
# Summary
# ===========================================================================

total=$((passed + failed))
eprint ""
eprint "=== Decision Index Validation Tests ==="
eprint "Passed: $passed / $total"
if [[ "$failed" -gt 0 ]]; then
	eprint "FAILED: $failed test(s)"
	exit 1
fi
eprint "All tests passed."
