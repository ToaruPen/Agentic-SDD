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

eprint "--- AC1: case-template-missing-required-field ---"
r2c="$(new_repo case-template-missing-required-field)"
cat >"$r2c/docs/decisions/_template.md" <<'EOF'
# Decision: template broken

## Decision-ID

D-YYYY-MM-DD-SHORT_KEBAB

## Context

- 背景:

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
write_valid_decision "$r2c" "D-2026-02-28-OK" "d-2026-02-28-ok.md"
write_valid_index "$r2c" "- D-2026-02-28-OK: [\`docs/decisions/d-2026-02-28-ok.md\`](./decisions/d-2026-02-28-ok.md)"
set +e
(cd "$r2c" && python3 ./scripts/validate-decision-index.py) >"$r2c/stdout" 2>"$r2c/stderr"
code_ac1_template_missing=$?
set -e

run_test "AC1: template missing field fails (exit!=0)" test "$code_ac1_template_missing" -ne 0
run_test "AC1: template missing field error is reported" grep -q "docs/decisions/_template.md: missing required section '## Rationale'" "$r2c/stderr"

eprint "--- AC1: case-missing-template-file ---"
r2d="$(new_repo case-missing-template-file)"
write_valid_decision "$r2d" "D-2026-02-28-OK" "d-2026-02-28-ok.md"
write_valid_index "$r2d" "- D-2026-02-28-OK: [\`docs/decisions/d-2026-02-28-ok.md\`](./decisions/d-2026-02-28-ok.md)"
set +e
(cd "$r2d" && python3 ./scripts/validate-decision-index.py) >"$r2d/stdout" 2>"$r2d/stderr"
code_ac1_template_absent=$?
set -e

run_test "AC1: missing template file fails (exit!=0)" test "$code_ac1_template_absent" -ne 0
run_test "AC1: missing template file error is reported" grep -q "docs/decisions/_template.md: missing template file" "$r2d/stderr"

eprint "--- AC1: case-fenced-heading-not-counted ---"
r2e="$(new_repo case-fenced-heading-not-counted)"
write_template "$r2e"
cat >"$r2e/docs/decisions/d-2026-02-28-fenced.md" <<'EOF'
# Decision: Fenced Heading

## Decision-ID

D-2026-02-28-FENCED

## Context

- 背景: test

```md
## Rationale
- this should not be treated as a section
```

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
write_valid_index "$r2e" "- D-2026-02-28-FENCED: [\`docs/decisions/d-2026-02-28-fenced.md\`](./decisions/d-2026-02-28-fenced.md)"
set +e
(cd "$r2e" && python3 ./scripts/validate-decision-index.py) >"$r2e/stdout" 2>"$r2e/stderr"
code_ac1_fenced_heading=$?
set -e

run_test "AC1: fenced heading does not satisfy required section (exit!=0)" test "$code_ac1_fenced_heading" -ne 0
run_test "AC1: fenced heading case reports missing Rationale" grep -q "Rationale" "$r2e/stderr"

eprint "--- AC1: case-malformed-decision-id-value ---"
r2b="$(new_repo case-malformed-decision-id-value)"
write_template "$r2b"
cat >"$r2b/docs/decisions/d-2026-02-28-malformed.md" <<'EOF'
# Decision: Malformed ID

## Decision-ID

D-2026-02-28-MALFORMED extra

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
write_valid_index "$r2b" "- D-2026-02-28-MALFORMED: [\`docs/decisions/d-2026-02-28-malformed.md\`](./decisions/d-2026-02-28-malformed.md)"
set +e
(cd "$r2b" && python3 ./scripts/validate-decision-index.py) >"$r2b/stdout" 2>"$r2b/stderr"
code_ac1_malformed_id=$?
set -e

run_test "AC1: malformed Decision-ID value fails (exit!=0)" test "$code_ac1_malformed_id" -ne 0
run_test "AC1: malformed Decision-ID error is reported" grep -q "missing or invalid Decision-ID value" "$r2b/stderr"

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

eprint "--- AC2: case-display-link-path-mismatch ---"
r5d="$(new_repo case-display-link-path-mismatch)"
write_template "$r5d"
write_valid_decision "$r5d" "D-2026-02-28-LINKCHK" "d-2026-02-28-linkchk.md"
write_valid_index "$r5d" "- D-2026-02-28-LINKCHK: [\`docs/decisions/d-2026-02-28-linkchk.md\`](./decisions/d-2026-02-28-missing.md)"
set +e
(cd "$r5d" && python3 ./scripts/validate-decision-index.py) >"$r5d/stdout" 2>"$r5d/stderr"
code_ac2_link_path=$?
set -e

run_test "AC2: broken markdown link path fails (exit!=0)" test "$code_ac2_link_path" -ne 0
run_test "AC2: error uses link destination path" grep -q "d-2026-02-28-missing.md" "$r5d/stderr"

eprint "--- AC2: case-wrong-directory-link ---"
r5e="$(new_repo case-wrong-directory-link)"
write_template "$r5e"
write_valid_decision "$r5e" "D-2026-02-28-WRONGDIR" "d-2026-02-28-wrongdir.md"
write_valid_index "$r5e" "- D-2026-02-28-WRONGDIR: [\`docs/decisions/d-2026-02-28-wrongdir.md\`](./wrong-dir/d-2026-02-28-wrongdir.md)"
set +e
(cd "$r5e" && python3 ./scripts/validate-decision-index.py) >"$r5e/stdout" 2>"$r5e/stderr"
code_ac2_wrong_dir=$?
set -e

run_test "AC2: wrong-directory link fails (exit!=0)" test "$code_ac2_wrong_dir" -ne 0
run_test "AC2: wrong-directory error is reported" grep -q "docs/decisions/\*.md" "$r5e/stderr"

eprint "--- AC2: case-subdir-shadowing-same-filename ---"
r5f="$(new_repo case-subdir-shadowing-same-filename)"
write_template "$r5f"
write_valid_decision "$r5f" "D-2026-02-28-SHADOW" "d-2026-02-28-shadow.md"
mkdir -p "$r5f/docs/decisions/subdir"
cp "$r5f/docs/decisions/d-2026-02-28-shadow.md" "$r5f/docs/decisions/subdir/d-2026-02-28-shadow.md"
write_valid_index "$r5f" "- D-2026-02-28-SHADOW: [\`docs/decisions/d-2026-02-28-shadow.md\`](./decisions/subdir/d-2026-02-28-shadow.md)"
set +e
(cd "$r5f" && python3 ./scripts/validate-decision-index.py) >"$r5f/stdout" 2>"$r5f/stderr"
code_ac2_subdir_shadow=$?
set -e

run_test "AC2: subdir shadowing path fails (exit!=0)" test "$code_ac2_subdir_shadow" -ne 0
run_test "AC2: unmanaged-file error is reported" grep -q "Index references unmanaged file" "$r5f/stderr"

eprint "--- AC2: case-docs-prefix-link-is-invalid ---"
r5g="$(new_repo case-docs-prefix-link-is-invalid)"
write_template "$r5g"
write_valid_decision "$r5g" "D-2026-02-28-DOCSPREFIX" "d-2026-02-28-docsprefix.md"
write_valid_index "$r5g" "- D-2026-02-28-DOCSPREFIX: [\`docs/decisions/d-2026-02-28-docsprefix.md\`](docs/decisions/d-2026-02-28-docsprefix.md)"
set +e
(cd "$r5g" && python3 ./scripts/validate-decision-index.py) >"$r5g/stdout" 2>"$r5g/stderr"
code_ac2_docs_prefix=$?
set -e

run_test "AC2: docs-prefix link fails (exit!=0)" test "$code_ac2_docs_prefix" -ne 0
run_test "AC2: docs-prefix link error is reported" grep -q "must start with './decisions/'" "$r5g/stderr"

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

eprint "--- AC3: case-multi-id-single-line ---"
r7b="$(new_repo case-multi-id-single-line)"
write_template "$r7b"
write_valid_decision "$r7b" "D-2026-02-01-OLD" "d-2026-02-01-old.md"
cat >"$r7b/docs/decisions/d-2026-02-28-multi.md" <<'EOF'
# Decision: Multi ID Supersedes

## Decision-ID

D-2026-02-28-MULTI

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

- D-2026-02-01-OLD, D-2026-01-01-NONEXISTENT

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r7b" \
	"- D-2026-02-01-OLD: [\`docs/decisions/d-2026-02-01-old.md\`](./decisions/d-2026-02-01-old.md)" \
	"- D-2026-02-28-MULTI: [\`docs/decisions/d-2026-02-28-multi.md\`](./decisions/d-2026-02-28-multi.md)"
set +e
(cd "$r7b" && python3 ./scripts/validate-decision-index.py) >"$r7b/stdout" 2>"$r7b/stderr"
code_ac3_multi=$?
set -e

run_test "AC3: multi-ID line catches all IDs" test "$code_ac3_multi" -ne 0
run_test "AC3: multi-ID line reports nonexistent ID" grep -q "D-2026-01-01-NONEXISTENT" "$r7b/stderr"

eprint "--- AC3: case-invalid-supersedes-format ---"
r7c="$(new_repo case-invalid-supersedes-format)"
write_template "$r7c"
cat >"$r7c/docs/decisions/d-2026-02-28-invalid-supersedes.md" <<'EOF'
# Decision: Invalid Supersedes Format

## Decision-ID

D-2026-02-28-INVALID_SUPERSEDES

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

- d-2026-02-01-lowercase

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r7c" "- D-2026-02-28-INVALID_SUPERSEDES: [\`docs/decisions/d-2026-02-28-invalid-supersedes.md\`](./decisions/d-2026-02-28-invalid-supersedes.md)"
set +e
(cd "$r7c" && python3 ./scripts/validate-decision-index.py) >"$r7c/stdout" 2>"$r7c/stderr"
code_ac3_invalid_fmt=$?
set -e

run_test "AC3: invalid supersedes format fails (exit!=0)" test "$code_ac3_invalid_fmt" -ne 0
run_test "AC3: invalid supersedes entry error is reported" grep -q "invalid Supersedes entry" "$r7c/stderr"

eprint "--- AC3: case-partial-match-supersedes-format ---"
r7d="$(new_repo case-partial-match-supersedes-format)"
write_template "$r7d"
write_valid_decision "$r7d" "D-2026-02-01-OLD" "d-2026-02-01-old.md"
cat >"$r7d/docs/decisions/d-2026-02-28-partial.md" <<'EOF'
# Decision: Partial Match Supersedes

## Decision-ID

D-2026-02-28-PARTIAL

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

- D-2026-02-01-OLD-extra

## Inputs Fingerprint

- PRD: N/A
EOF
write_valid_index "$r7d" \
	"- D-2026-02-01-OLD: [\`docs/decisions/d-2026-02-01-old.md\`](./decisions/d-2026-02-01-old.md)" \
	"- D-2026-02-28-PARTIAL: [\`docs/decisions/d-2026-02-28-partial.md\`](./decisions/d-2026-02-28-partial.md)"
set +e
(cd "$r7d" && python3 ./scripts/validate-decision-index.py) >"$r7d/stdout" 2>"$r7d/stderr"
code_ac3_partial=$?
set -e

run_test "AC3: partial-match supersedes format fails (exit!=0)" test "$code_ac3_partial" -ne 0
run_test "AC3: partial-match supersedes is flagged invalid" grep -q "invalid Supersedes entry" "$r7d/stderr"

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

eprint "--- Edge: case-missing-decision-index-section ---"
r9b="$(new_repo case-missing-decision-index-section)"
write_template "$r9b"
write_valid_decision "$r9b" "D-2026-02-28-VALID" "d-2026-02-28-valid.md"
cat >"$r9b/docs/decisions.md" <<'EOF'
# 意思決定ログ（Decision Snapshot）

## Not Decision Index

- D-2026-02-28-VALID: [`docs/decisions/d-2026-02-28-valid.md`](./decisions/d-2026-02-28-valid.md)
EOF
set +e
(cd "$r9b" && python3 ./scripts/validate-decision-index.py) >"$r9b/stdout" 2>"$r9b/stderr"
code_missing_index_section=$?
set -e

run_test "Edge: missing Decision Index section fails (exit!=0)" test "$code_missing_index_section" -ne 0
run_test "Edge: missing section error is reported" grep -q "Missing section '## Decision Index'" "$r9b/stderr"

eprint "--- Edge: case-invalid-index-line ---"
r10="$(new_repo case-invalid-index-line)"
write_template "$r10"
write_valid_decision "$r10" "D-2026-02-28-VALID" "d-2026-02-28-valid.md"
cat >"$r10/docs/decisions.md" <<'EOF'
# 意思決定ログ（Decision Snapshot）

## Decision Index

this line is invalid
EOF
set +e
(cd "$r10" && python3 ./scripts/validate-decision-index.py) >"$r10/stdout" 2>"$r10/stderr"
code_invalid_index_line=$?
set -e

run_test "Edge: invalid non-empty index line fails (exit!=0)" test "$code_invalid_index_line" -ne 0
run_test "Edge: invalid line error is reported" grep -q "Invalid Decision Index line" "$r10/stderr"

eprint "--- Edge: case-level3-subheading-in-index ---"
r11="$(new_repo case-level3-subheading-in-index)"
write_template "$r11"
write_valid_decision "$r11" "D-2026-02-28-SUBHEAD" "d-2026-02-28-subhead.md"
cat >"$r11/docs/decisions.md" <<'EOF'
# 意思決定ログ（Decision Snapshot）

## Decision Index

### Group A
- D-2026-02-28-SUBHEAD: [`docs/decisions/d-2026-02-28-subhead.md`](./decisions/d-2026-02-28-subhead.md)
EOF
run_test "Edge: level-3 subheading inside index is allowed" bash -c "(cd '$r11' && python3 ./scripts/validate-decision-index.py)"

eprint "--- Edge: case-multiline-html-comment-in-index ---"
r12="$(new_repo case-multiline-html-comment-in-index)"
write_template "$r12"
write_valid_decision "$r12" "D-2026-02-28-COMMENT" "d-2026-02-28-comment.md"
cat >"$r12/docs/decisions.md" <<'EOF'
# 意思決定ログ（Decision Snapshot）

## Decision Index

<!--
multiline note
still comment
-->

- D-2026-02-28-COMMENT: [`docs/decisions/d-2026-02-28-comment.md`](./decisions/d-2026-02-28-comment.md)
EOF
run_test "Edge: multiline HTML comment inside index is ignored" bash -c "(cd '$r12' && python3 ./scripts/validate-decision-index.py)"

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
