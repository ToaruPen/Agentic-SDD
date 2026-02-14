#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-ruff-gate)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

work="$tmpdir/work"
remote="$tmpdir/remote.git"
venv="$tmpdir/venv"

python3 -m venv "$venv"
# shellcheck disable=SC1091
source "$venv/bin/activate"
python -m pip -q install --upgrade pip >/dev/null
python -m pip -q install -r "$repo_root/requirements-dev.txt" >/dev/null
export PATH="$venv/bin:$PATH"

mkdir -p "$work"
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

mkdir -p "$work/scripts" "$work/scripts/tests" "$work/.githooks"
cp -p "$repo_root/scripts/validate-approval.py" "$work/scripts/validate-approval.py"
cp -p "$repo_root/scripts/validate-worktree.py" "$work/scripts/validate-worktree.py"
cp -p "$repo_root/.githooks/pre-commit" "$work/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$work/.githooks/pre-push"
cp -p "$repo_root/pyproject.toml" "$work/pyproject.toml"
cp -p "$repo_root/requirements-dev.txt" "$work/requirements-dev.txt"

chmod +x "$work/scripts/validate-approval.py"
chmod +x "$work/scripts/validate-worktree.py"
chmod +x "$work/.githooks/pre-commit" "$work/.githooks/pre-push"

git -C "$work" config core.hooksPath .githooks
git -C "$work" checkout -b "feature/ruff-gate-test" -q

cat > "$work/scripts/bad.py" <<'EOF'
import os

print("x")
EOF
git -C "$work" add "$work/scripts/bad.py"

set +e
git -C "$work" commit -m "test: ruff should block" -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected commit to be blocked by ruff gate"
  exit 1
fi

cat > "$work/scripts/bad.py" <<'EOF'
print("x")
EOF
git -C "$work" add "$work/scripts/bad.py"
git -C "$work" commit -m "test: ruff should pass" -q

git init --bare -q "$remote"
git -C "$work" remote add origin "$remote"
git -C "$work" push -u origin HEAD -q

cat > "$work/scripts/bad2.py" <<'EOF'
import os

print("y")
EOF
git -C "$work" add "$work/scripts/bad2.py"

# Bypass pre-commit to ensure pre-push blocks.
git -C "$work" commit -m "test: bypass pre-commit" --no-verify -q

set +e
git -C "$work" push -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected push to be blocked by ruff gate"
  exit 1
fi

cat > "$work/scripts/bad2.py" <<'EOF'
print("y")
EOF
git -C "$work" add "$work/scripts/bad2.py"
git -C "$work" commit -m "test: fix before push" -q
git -C "$work" push -q

printf '%s\n' "OK: ruff gate smoke test passed"
