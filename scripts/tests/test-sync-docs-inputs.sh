#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
resolver_py_src="$repo_root/scripts/resolve-sync-docs-inputs.py"
sot_refs_src="$repo_root/scripts/sot_refs.py"

if [[ ! -f "$resolver_py_src" ]]; then
  eprint "Missing resolver: $resolver_py_src"
  exit 1
fi

if [[ ! -f "$sot_refs_src" ]]; then
  eprint "Missing sot refs: $sot_refs_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-sync-docs-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q

mkdir -p "$tmpdir/scripts"
cp -p "$resolver_py_src" "$tmpdir/scripts/resolve-sync-docs-inputs.py"
cp -p "$sot_refs_src" "$tmpdir/scripts/sot_refs.py"
chmod +x "$tmpdir/scripts/resolve-sync-docs-inputs.py"

# Minimal repo content
mkdir -p "$tmpdir/docs/prd" "$tmpdir/docs/epics" "$tmpdir/src"

cat > "$tmpdir/docs/prd/prd.md" <<'EOF'
# PRD: Test

## 4. 機能要件

FR

## 5. 受け入れ条件（AC）

- [ ] AC-1
EOF

cat > "$tmpdir/docs/epics/epic.md" <<'EOF'
# Epic: Test

- 参照PRD: `docs/prd/prd.md`

## 3. 技術設計

design
EOF

cat > "$tmpdir/src/hello.txt" <<'EOF'
hello
EOF

git -C "$tmpdir" add docs/prd/prd.md docs/epics/epic.md src/hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q

# Issue body fixture (offline)
cat > "$tmpdir/issue-body.md" <<'EOF'
## 背景

- Epic: docs/epics/epic.md
- PRD: docs/prd/prd.md
EOF

# Staged diff only -> diff_source=staged
echo "change1" >> "$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt

out_json="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
  python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode auto)"

prd_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["prd_path"])' <<<"$out_json")"
epic_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_json")"
diff_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_json")"
diff_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_path"])' <<<"$out_json")"

if [[ "$prd_path" != "docs/prd/prd.md" ]]; then
  eprint "Expected PRD path docs/prd/prd.md, got: $prd_path"
  exit 1
fi

if [[ "$epic_path" != "docs/epics/epic.md" ]]; then
  eprint "Expected Epic path docs/epics/epic.md, got: $epic_path"
  exit 1
fi

if [[ "$diff_source" != "staged" ]]; then
  eprint "Expected diff_source staged, got: $diff_source"
  exit 1
fi

if [[ ! -s "$tmpdir/$diff_path" ]]; then
  eprint "Expected diff patch to exist and be non-empty: $tmpdir/$diff_path"
  exit 1
fi

# Both staged and worktree diffs -> should fail-fast
echo "change2" >> "$tmpdir/src/hello.txt"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
  python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode auto) >/dev/null 2>"$tmpdir/stderr-both"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when both staged and worktree diffs exist"
  exit 1
fi

if ! grep -q "Both staged and worktree diffs are non-empty" "$tmpdir/stderr-both"; then
  eprint "Expected ambiguity error message, got:"
  cat "$tmpdir/stderr-both" >&2
  exit 1
fi

# Reset to a clean state for the next cases
git -C "$tmpdir" reset --hard -q HEAD

# PRD auto-resolution should fail when multiple PRDs exist and no Issue refs
cat > "$tmpdir/docs/prd/other.md" <<'EOF'
# PRD: Other
EOF

echo "change3" >> "$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt

set +e
(cd "$tmpdir" && OUTPUT_ROOT="$tmpdir/out" python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode staged) \
  >/dev/null 2>"$tmpdir/stderr-multi"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when multiple PRDs exist"
  exit 1
fi

if ! grep -q "Multiple PRDs exist" "$tmpdir/stderr-multi"; then
  eprint "Expected multiple PRDs error, got:"
  cat "$tmpdir/stderr-multi" >&2
  exit 1
fi

# With --prd explicitly set, Epic should be resolved by PRD reference and succeed
out_json2="$(cd "$tmpdir" && OUTPUT_ROOT="$tmpdir/out" \
  python3 ./scripts/resolve-sync-docs-inputs.py --prd docs/prd/prd.md --diff-mode staged)"

epic_path2="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_json2")"
if [[ "$epic_path2" != "docs/epics/epic.md" ]]; then
  eprint "Expected Epic path docs/epics/epic.md, got: $epic_path2"
  exit 1
fi

# Placeholder refs should fail-fast
cat > "$tmpdir/issue-placeholder.md" <<'EOF'
## 背景

- Epic: docs/epics/epic.md
- PRD: <!-- PRDファイルへのリンク -->
EOF

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-placeholder.md" OUTPUT_ROOT="$tmpdir/out" \
  python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode staged) >/dev/null 2>"$tmpdir/stderr-placeholder"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when PRD reference is placeholder"
  exit 1
fi

if ! grep -q "PRD reference is required" "$tmpdir/stderr-placeholder"; then
  eprint "Expected placeholder error message, got:"
  cat "$tmpdir/stderr-placeholder" >&2
  exit 1
fi

eprint "OK: scripts/tests/test-sync-docs-inputs.sh"
