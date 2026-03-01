#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
resolver_py_src="$repo_root/scripts/extract/resolve_sync_docs_inputs.py"
resolver_legacy_src="$repo_root/scripts/resolve-sync-docs-inputs.py"
sot_refs_src="$repo_root/scripts/_lib/sot_refs.py"

if [[ ! -f "$resolver_py_src" ]]; then
	eprint "Missing resolver: $resolver_py_src"
	exit 1
fi

if [[ ! -f "$sot_refs_src" ]]; then
	eprint "Missing sot refs: $sot_refs_src"
	exit 1
fi

if [[ ! -f "$resolver_legacy_src" ]]; then
	eprint "Missing legacy resolver wrapper: $resolver_legacy_src"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-sync-docs-test)"
external_root=""
cleanup() {
	rm -rf "$tmpdir"
	if [[ -n "$external_root" ]]; then
		rm -rf "$external_root"
	fi
}
trap cleanup EXIT

git -C "$tmpdir" init -q

mkdir -p "$tmpdir/scripts/extract"
cp -p "$resolver_py_src" "$tmpdir/scripts/extract/resolve_sync_docs_inputs.py"
cp -p "$resolver_legacy_src" "$tmpdir/scripts/resolve-sync-docs-inputs.py"
cp -rp "$repo_root/scripts/_lib" "$tmpdir/scripts/"
chmod +x "$tmpdir/scripts/extract/resolve_sync_docs_inputs.py"
chmod +x "$tmpdir/scripts/resolve-sync-docs-inputs.py"

# Minimal repo content
mkdir -p "$tmpdir/docs/prd" "$tmpdir/docs/epics" "$tmpdir/src"

cat >"$tmpdir/docs/prd/prd.md" <<'EOF'
# PRD: Test

## 4. 機能要件

FR

## 5. 受け入れ条件（AC）

- [ ] AC-1
EOF

cat >"$tmpdir/docs/epics/epic.md" <<'EOF'
# Epic: Test

- 参照PRD: `docs/prd/prd.md`

## 3. 技術設計

design
EOF

cat >"$tmpdir/src/hello.txt" <<'EOF'
hello
EOF

git -C "$tmpdir" add docs/prd/prd.md docs/epics/epic.md src/hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$tmpdir" branch -M main

# Issue body fixture (offline)
cat >"$tmpdir/issue-body.md" <<'EOF'
## 背景

- Epic: docs/epics/epic.md
- PRD: docs/prd/prd.md
EOF

# Staged diff only -> diff_source=staged
echo "change1" >>"$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt

out_json="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode auto)"

out_json_legacy="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out-legacy" \
	python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode auto)"

cat >"$tmpdir/sitecustomize.py" <<'EOF'
import sys


class _StderrProxy:
    def __init__(self, stream):
        self._stream = stream

    def isatty(self):
        return True

    def __getattr__(self, name):
        return getattr(self._stream, name)


sys.stderr = _StderrProxy(sys.stderr)
EOF

set +e
(cd "$tmpdir" && PYTHONPATH="$tmpdir${PYTHONPATH:+:$PYTHONPATH}" GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out-legacy-warn" \
	python3 ./scripts/resolve-sync-docs-inputs.py --diff-mode auto >/dev/null 2>"$tmpdir/stderr-legacy")
legacy_rc=$?
set -e

if [[ "$legacy_rc" -ne 0 ]]; then
	eprint "Expected legacy wrapper to exit successfully, got: $legacy_rc"
	exit 1
fi

if ! grep -qi "deprecated" "$tmpdir/stderr-legacy"; then
	eprint "Expected deprecation warning from legacy wrapper"
	cat "$tmpdir/stderr-legacy" >&2
	exit 1
fi

prd_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["prd_path"])' <<<"$out_json")"
epic_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_json")"
diff_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_json")"
diff_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_path"])' <<<"$out_json")"
legacy_diff_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_json_legacy")"
legacy_diff_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_path"])' <<<"$out_json_legacy")"

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

if [[ "$legacy_diff_source" != "staged" ]]; then
	eprint "Expected legacy diff_source staged, got: $legacy_diff_source"
	exit 1
fi

if [[ ! -s "$tmpdir/$legacy_diff_path" ]]; then
	eprint "Expected legacy diff patch to exist and be non-empty: $tmpdir/$legacy_diff_path"
	exit 1
fi

# Both staged and worktree diffs -> should fail-fast
echo "change2" >>"$tmpdir/src/hello.txt"

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode auto) >/dev/null 2>"$tmpdir/stderr-both"
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
cat >"$tmpdir/docs/prd/other.md" <<'EOF'
# PRD: Other
EOF

echo "change3" >>"$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt

set +e
(cd "$tmpdir" && OUTPUT_ROOT="$tmpdir/out" python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode staged) \
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
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --prd docs/prd/prd.md --diff-mode staged)"

epic_path2="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_json2")"
if [[ "$epic_path2" != "docs/epics/epic.md" ]]; then
	eprint "Expected Epic path docs/epics/epic.md, got: $epic_path2"
	exit 1
fi

# Placeholder refs should fail-fast (placeholder PRD → auto-detect → multiple PRDs)
cat >"$tmpdir/issue-placeholder.md" <<'EOF'
## 背景

- Epic: docs/epics/epic.md
- PRD: <!-- PRDファイルへのリンク -->
EOF

set +e
(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-placeholder.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode staged) >/dev/null 2>"$tmpdir/stderr-placeholder"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
	eprint "Expected failure when PRD reference is placeholder"
	exit 1
fi

if ! grep -q "Multiple PRDs exist" "$tmpdir/stderr-placeholder"; then
	eprint "Expected multiple PRDs error for placeholder ref, got:"
	cat "$tmpdir/stderr-placeholder" >&2
	exit 1
fi

git -C "$tmpdir" reset --hard -q HEAD
echo "worktree-change" >>"$tmpdir/src/hello.txt"
out_worktree="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode worktree)"
worktree_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_worktree")"
worktree_epic="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_worktree")"
if [[ "$worktree_source" != "worktree" ]]; then
	eprint "Expected diff_source worktree, got: $worktree_source"
	exit 1
fi
if [[ "$worktree_epic" != "docs/epics/epic.md" ]]; then
	eprint "Expected Epic path docs/epics/epic.md for worktree mode, got: $worktree_epic"
	exit 1
fi

git -C "$tmpdir" reset --hard -q HEAD
git -C "$tmpdir" checkout -q -b issue-range
echo "range-change" >>"$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "range-change" -q
out_range="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode range)"
range_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_range")"
range_detail="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_detail"])' <<<"$out_range")"
range_epic="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_range")"
if [[ "$range_source" != "range" ]]; then
	eprint "Expected diff_source range, got: $range_source"
	exit 1
fi
if [[ "$range_detail" != "main" ]]; then
	eprint "Expected diff_detail main via origin/main fallback, got: $range_detail"
	exit 1
fi
if [[ "$range_epic" != "docs/epics/epic.md" ]]; then
	eprint "Expected Epic path docs/epics/epic.md for range mode, got: $range_epic"
	exit 1
fi

mkdir -p "$tmpdir/fakebin"
cat >"$tmpdir/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh mocked failure" >&2
exit 1
EOF
chmod +x "$tmpdir/fakebin/gh"

set +e
(cd "$tmpdir" && PATH="$tmpdir/fakebin:$PATH" GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode pr --pr 200) >/dev/null 2>"$tmpdir/stderr-pr"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
	eprint "Expected failure when gh pr diff fails in diff-mode pr"
	exit 1
fi
if ! grep -q "Failed to fetch PR diff via gh" "$tmpdir/stderr-pr"; then
	eprint "Expected gh failure message for diff-mode pr, got:"
	cat "$tmpdir/stderr-pr" >&2
	exit 1
fi

echo "dry-run-change" >>"$tmpdir/src/hello.txt"
git -C "$tmpdir" add src/hello.txt
dry_root="$tmpdir/out-dry"
out_dry="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode staged --dry-run --output-root "$dry_root")"
dry_source="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_source"])' <<<"$out_dry")"
if [[ "$dry_source" != "staged" ]]; then
	eprint "Expected diff_source staged for dry-run, got: $dry_source"
	exit 1
fi
if [[ -d "$dry_root" ]]; then
	eprint "Expected no output directory creation in dry-run: $dry_root"
	exit 1
fi

custom_run_id="run-id-12345"
out_run_id="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode staged --dry-run --run-id "$custom_run_id")"
run_id_value="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["run_id"])' <<<"$out_run_id")"
if [[ "$run_id_value" != "$custom_run_id" ]]; then
	eprint "Expected run_id $custom_run_id, got: $run_id_value"
	exit 1
fi

external_root="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-sync-docs-out)"
out_external="$(cd "$tmpdir" && GH_ISSUE_BODY_FILE="$tmpdir/issue-body.md" OUTPUT_ROOT="$tmpdir/out" \
	python3 ./scripts/extract/resolve_sync_docs_inputs.py --diff-mode staged --output-root "$external_root")"
external_diff_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["diff_path"])' <<<"$out_external")"
external_epic_path="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["epic_path"])' <<<"$out_external")"
if [[ "$external_diff_path" != /* ]]; then
	external_diff_path="$tmpdir/$external_diff_path"
fi
if [[ ! -s "$external_diff_path" ]]; then
	eprint "Expected diff patch in external output-root, got missing path: $external_diff_path"
	exit 1
fi
if [[ "$external_epic_path" != "docs/epics/epic.md" ]]; then
	eprint "Expected Epic path docs/epics/epic.md for external output-root, got: $external_epic_path"
	exit 1
fi

eprint "OK: scripts/tests/test-sync-docs-inputs.sh"
