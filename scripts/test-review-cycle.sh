#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
schema_src="${repo_root}/.agent/schemas/review.json"
review_cycle_sh="${repo_root}/scripts/review-cycle.sh"
validator_py="${repo_root}/scripts/validate-review-json.py"

if [[ ! -f "$schema_src" ]]; then
  eprint "Missing schema: $schema_src"
  exit 1
fi

if [[ ! -x "$review_cycle_sh" ]]; then
  eprint "Missing script or not executable: $review_cycle_sh"
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
