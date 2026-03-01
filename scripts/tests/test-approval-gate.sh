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

echo "init" >"$work/init.txt"
git -C "$work" add init.txt
git -C "$work" commit -m "test: init" -q

mkdir -p "$work/scripts/gates" "$work/scripts/approval" "$work/.githooks"
cp -p "$repo_root/scripts/gates/validate_approval.py" "$work/scripts/gates/validate_approval.py"
cp -p "$repo_root/scripts/gates/validate_worktree.py" "$work/scripts/gates/validate_worktree.py"
cp -p "$repo_root/scripts/approval/create_approval.py" "$work/scripts/approval/create_approval.py"
cp -rp "$repo_root/scripts/_lib" "$work/scripts/"
cp -p "$repo_root/.githooks/pre-commit" "$work/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$work/.githooks/pre-push"

chmod +x "$work/scripts/gates/validate_approval.py" "$work/scripts/approval/create_approval.py"
chmod +x "$work/scripts/gates/validate_worktree.py"
chmod +x "$work/.githooks/pre-commit" "$work/.githooks/pre-push"

git -C "$work" config core.hooksPath .githooks

git -C "$work" worktree add "$wt" -b "feature/issue-123-approval-gate" -q

mkdir -p "$wt/scripts/gates" "$wt/scripts/approval" "$wt/.githooks"
cp -p "$repo_root/scripts/gates/validate_approval.py" "$wt/scripts/gates/validate_approval.py"
cp -p "$repo_root/scripts/gates/validate_worktree.py" "$wt/scripts/gates/validate_worktree.py"
cp -p "$repo_root/scripts/approval/create_approval.py" "$wt/scripts/approval/create_approval.py"
cp -rp "$repo_root/scripts/_lib" "$wt/scripts/"
cp -p "$repo_root/.githooks/pre-commit" "$wt/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$wt/.githooks/pre-push"

chmod +x "$wt/scripts/gates/validate_approval.py" "$wt/scripts/approval/create_approval.py" "$wt/scripts/gates/validate_worktree.py"
chmod +x "$wt/.githooks/pre-commit" "$wt/.githooks/pre-push"

echo "a" >"$wt/a.txt"
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
cat >"$wt/.agentic-sdd/approvals/issue-123/estimate.md" <<'EOF'
## Full見積もり

### 1. 依頼内容の解釈

テスト用見積もり
EOF

assert_invalid_approval_args() {
	local expected_validate_rc="$1"

	set +e
	(cd "$wt" && python3 scripts/approval/create_approval.py --issue 123 --mode impl --mode-source invalid-source --mode-reason 'test: invalid mode source' >/dev/null 2>"$tmpdir/stderr_invalid_mode_source")
	rc_create_invalid_source=$?
	set -e
	if [[ "$rc_create_invalid_source" -eq 0 ]]; then
		eprint "FAIL: expected create-approval.py to reject invalid --mode-source"
		exit 1
	fi

	set +e
	(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null 2>"$tmpdir/stderr_validate_after_invalid_mode_source")
	rc_validate_invalid_source=$?
	set -e
	if [[ "$rc_validate_invalid_source" -ne "$expected_validate_rc" ]]; then
		eprint "FAIL: unexpected validate-approval.py rc after invalid --mode-source (expected $expected_validate_rc, got $rc_validate_invalid_source)"
		exit 1
	fi

	set +e
	(cd "$wt" && python3 scripts/approval/create_approval.py --issue 123 --mode impl --mode-source agent-heuristic --mode-reason '   ' >/dev/null 2>"$tmpdir/stderr_blank_mode_reason")
	rc_create_blank_reason=$?
	set -e
	if [[ "$rc_create_blank_reason" -eq 0 ]]; then
		eprint "FAIL: expected create-approval.py to reject blank --mode-reason"
		exit 1
	fi

	set +e
	(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null 2>"$tmpdir/stderr_validate_after_blank_mode_reason")
	rc_validate_blank_reason=$?
	set -e
	if [[ "$rc_validate_blank_reason" -ne "$expected_validate_rc" ]]; then
		eprint "FAIL: unexpected validate-approval.py rc after blank --mode-reason (expected $expected_validate_rc, got $rc_validate_blank_reason)"
		exit 1
	fi
}

assert_invalid_approval_args 2

(cd "$wt" && python3 scripts/approval/create_approval.py --issue 123 --mode impl --mode-source agent-heuristic --mode-reason 'test: default impl mode' >/dev/null)
(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null)

python3 - "$wt/.agentic-sdd/approvals/issue-123/approval.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
obj = json.loads(path.read_text(encoding="utf-8"))
obj["approved_at"] = "2026-02-30T00:00:00Z"
path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

set +e
(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null 2>"$tmpdir/stderr_invalid_approved_at")
rc_invalid_approved_at=$?
set -e
if [[ "$rc_invalid_approved_at" -ne 2 ]]; then
	eprint "FAIL: expected validate_approval.py to block invalid approved_at"
	exit 1
fi
if ! grep -q "approved_at must be a valid UTC timestamp" "$tmpdir/stderr_invalid_approved_at"; then
	eprint "FAIL: expected invalid approved_at message"
	cat "$tmpdir/stderr_invalid_approved_at" >&2
	exit 1
fi

python3 - "$wt/.agentic-sdd/approvals/issue-123/approval.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
obj = json.loads(path.read_text(encoding="utf-8"))
obj["approved_at"] = "2026-02-01T00:00:00Z"
obj["approver"] = "   "
path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

set +e
(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null 2>"$tmpdir/stderr_blank_approver")
rc_blank_approver=$?
set -e
if [[ "$rc_blank_approver" -ne 2 ]]; then
	eprint "FAIL: expected validate_approval.py to block blank approver"
	exit 1
fi
if ! grep -q "approver must be a non-empty string" "$tmpdir/stderr_blank_approver"; then
	eprint "FAIL: expected blank approver message"
	cat "$tmpdir/stderr_blank_approver" >&2
	exit 1
fi

(cd "$wt" && python3 scripts/approval/create_approval.py --issue 123 --mode impl --mode-source agent-heuristic --mode-reason 'test: restore valid approval after validation checks' --force >/dev/null)
(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null)

git -C "$wt" commit -m "test: should pass" -q

# Setup a local remote to test pre-push.
git init --bare -q "$remote"
git -C "$work" remote add origin "$remote"
git -C "$wt" push -u origin HEAD -q

# Drift without updating approval.json: push should be blocked.
echo "" >>"$wt/.agentic-sdd/approvals/issue-123/estimate.md"

set +e
git -C "$wt" push -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
	eprint "FAIL: expected push to be blocked after estimate drift"
	exit 1
fi

# Refresh approval and push should pass.
(cd "$wt" && python3 scripts/approval/create_approval.py --issue 123 --mode impl --mode-source agent-heuristic --mode-reason 'test: refreshed after drift' --force >/dev/null)
(cd "$wt" && python3 scripts/gates/validate_approval.py >/dev/null)

assert_invalid_approval_args 0

git -C "$wt" push -q

printf '%s\n' "OK: approval gate smoke test passed"
