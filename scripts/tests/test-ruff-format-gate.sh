#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-ruff-format-gate)"
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

mkdir -p "$work/scripts" "$work/.githooks"
cp -p "$repo_root/scripts/validate-approval.py" "$work/scripts/validate-approval.py"
cp -p "$repo_root/.githooks/pre-commit" "$work/.githooks/pre-commit"
cp -p "$repo_root/.githooks/pre-push" "$work/.githooks/pre-push"
cp -p "$repo_root/pyproject.toml" "$work/pyproject.toml"
cp -p "$repo_root/requirements-dev.txt" "$work/requirements-dev.txt"

chmod +x "$work/scripts/validate-approval.py"
chmod +x "$work/.githooks/pre-commit" "$work/.githooks/pre-push"

git -C "$work" config core.hooksPath .githooks
git -C "$work" checkout -b "feature/ruff-format-gate-test" -q

# 1) pre-commit should block when formatting is required.
cat > "$work/scripts/bad_format.py" <<'EOF'
print(  "x" )
EOF
git -C "$work" add "$work/scripts/bad_format.py"

set +e
git -C "$work" commit -m "test: ruff format should block" -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected commit to be blocked by ruff format gate"
  exit 1
fi

# 2) after formatting, commit should pass.
(cd "$work" && python3 -m ruff format scripts/bad_format.py >/dev/null)
git -C "$work" add "$work/scripts/bad_format.py"
git -C "$work" commit -m "test: ruff format should pass" -q

# 3) pre-push should block if commit bypasses pre-commit.
git init --bare -q "$remote"
git -C "$work" remote add origin "$remote"
git -C "$work" push -u origin HEAD -q

cat > "$work/scripts/bad_format2.py" <<'EOF'
print(  "y" )
EOF
git -C "$work" add "$work/scripts/bad_format2.py"

git -C "$work" commit -m "test: bypass pre-commit" --no-verify -q

set +e
git -C "$work" push -q
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "FAIL: expected push to be blocked by ruff format gate"
  exit 1
fi

(cd "$work" && python3 -m ruff format scripts/bad_format2.py >/dev/null)
git -C "$work" add "$work/scripts/bad_format2.py"
git -C "$work" commit -m "test: fix before push" -q
git -C "$work" push -q

printf '%s\n' "OK: ruff format gate smoke test passed"
