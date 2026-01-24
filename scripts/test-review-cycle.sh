#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Staged diff only (should succeed)
echo "change1" >> "$tmpdir/hello.txt"
git -C "$tmpdir" add hello.txt

(cd "$tmpdir" && SOT="test" TESTS="not run: reason" DIFF_MODE=auto \
  "$review_cycle_sh" issue-1 --dry-run) >/dev/null 2>/dev/null

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
  echo "missing --output-last-message" >&2
  exit 2
fi

mkdir -p "$(dirname "$out")"
cat > "$out" <<'JSON'
{
  "schema_version": 2,
  "scope_id": "issue-1",
  "facet": "Overall review (review-cycle)",
  "facet_slug": "overall",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "uncertainty": [],
  "overall_correctness": "patch is correct",
  "overall_explanation": "stub",
  "overall_confidence_score": 0.9
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
  CODEX_BIN="$tmpdir/codex" MODEL=stub REASONING_EFFORT=low \
  "$review_cycle_sh" issue-1 run1) >/dev/null

if [[ ! -f "$tmpdir/.agentic-sdd/reviews/issue-1/run1/review.json" ]]; then
  eprint "Expected review.json to be created"
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
  "schema_version": 2,
  "scope_id": "issue-1",
  "facet": "Overall review (review-cycle)",
  "facet_slug": "overall",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "uncertainty": [],
  "overall_correctness": "patch is correct",
  "overall_explanation": "No issues.",
  "overall_confidence_score": 0.9
}
EOF

python3 "$validator_py" "$tmpdir/review.json" --scope-id issue-1 --facet-slug overall >/dev/null

eprint "OK: scripts/test-review-cycle.sh"
