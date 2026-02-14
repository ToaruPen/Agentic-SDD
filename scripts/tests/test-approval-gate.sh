#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-approval-gate)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

work="$tmpdir/work"
wt="$tmpdir/wt"
remote="$tmpdir/remote.git"

mkdir -p "$work"
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

echo "init" > "$work/init.txt"
git -C "$work" add init.txt
git -C "$work" commit -m "test: init" -q

mkdir -p "$work/scripts" "$work/.githooks"
cp -p "$repo_root/scripts/validate-approval.py" "$work/scripts/validate-approval.py"
cp -p "$repo_root/scripts/validate-worktree.py" "$work/scripts/validate-worktree.py"
cp -p "$repo_root/scripts/create-approval.py" "$work/scripts/create-approval.py"
cp -p "$repo_root/.githooks/pre-commit" "$work/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$work/.githooks/pre-push"

chmod +x "$work/scripts/validate-approval.py" "$work/scripts/create-approval.py"
chmod +x "$work/scripts/validate-worktree.py"
chmod +x "$work/.githooks/pre-commit" "$work/.githooks/pre-push"

git -C "$work" config core.hooksPath .githooks

git -C "$work" worktree add "$wt" -b "feature/issue-123-approval-gate" -q

mkdir -p "$wt/scripts" "$wt/.githooks"
cp -p "$repo_root/scripts/validate-approval.py" "$wt/scripts/validate-approval.py"
cp -p "$repo_root/scripts/validate-worktree.py" "$wt/scripts/validate-worktree.py"
cp -p "$repo_root/scripts/create-approval.py" "$wt/scripts/create-approval.py"
cp -p "$repo_root/.githooks/pre-commit" "$wt/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$wt/.githooks/pre-push"

chmod +x "$wt/scripts/validate-approval.py" "$wt/scripts/create-approval.py" "$wt/scripts/validate-worktree.py"
chmod +x "$wt/.githooks/pre-commit" "$wt/.githooks/pre-push"

echo "a" > "$wt/a.txt"
git -C "$wt" add a.txt

set +e
git -C "$wt" commit -m "test: should be blocked" -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected commit to be blocked without approval record"
  exit 1
fi

mkdir -p "$wt/.agentic-sdd/approvals/issue-123"
cat > "$wt/.agentic-sdd/approvals/issue-123/estimate.md" <<'EOF'
## Full見積もり

### 1. 依頼内容の解釈

テスト用見積もり
EOF

(cd "$wt" && python3 scripts/create-approval.py --issue 123 --mode impl >/dev/null)
(cd "$wt" && python3 scripts/validate-approval.py >/dev/null)

git -C "$wt" commit -m "test: should pass" -q

# Setup a local remote to test pre-push.
git init --bare -q "$remote"
git -C "$work" remote add origin "$remote"
git -C "$wt" push -u origin HEAD -q

# Drift without updating approval.json: push should be blocked.
echo "" >> "$wt/.agentic-sdd/approvals/issue-123/estimate.md"

set +e
git -C "$wt" push -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected push to be blocked after estimate drift"
  exit 1
fi

# Refresh approval and push should pass.
(cd "$wt" && python3 scripts/create-approval.py --issue 123 --mode impl --force >/dev/null)
(cd "$wt" && python3 scripts/validate-approval.py >/dev/null)

git -C "$wt" push -q

printf '%s\n' "OK: approval gate smoke test passed"
