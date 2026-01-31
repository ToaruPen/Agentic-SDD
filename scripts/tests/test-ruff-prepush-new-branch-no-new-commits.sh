#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-ruff-prepush)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

work="$tmpdir/work"
remote="$tmpdir/remote.git"
venv_ok="$tmpdir/venv_ok"
venv_no="$tmpdir/venv_no"

python3 -m venv "$venv_ok"
python3 -m venv "$venv_no"

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

git init --bare -q "$remote"
git -C "$work" remote add origin "$remote"

# 1) First push: include Python changes, with ruff available.
export PATH="$venv_ok/bin:$PATH"
python3 -m pip -q install --upgrade pip >/dev/null
python3 -m pip -q install -r "$work/requirements-dev.txt" >/dev/null

git -C "$work" checkout -b "feature/base" -q
mkdir -p "$work/scripts"
cat > "$work/scripts/ok.py" <<'EOF'
print("ok")
EOF
git -C "$work" add "$work/scripts/ok.py"

# Bypass pre-commit; we only care about pre-push behavior here.
git -C "$work" commit -m "test: add python file" --no-verify -q
git -C "$work" push -u origin HEAD -q

# Ensure remote-tracking refs exist so `git rev-list <sha> --not --remotes` can be empty.
git -C "$work" fetch -q origin

# 2) Second push: new branch pointing to the same (already-remote) commit, with ruff unavailable.
export PATH="$venv_no/bin:/usr/bin:/bin"

sha="$(git -C "$work" rev-parse HEAD)"
git -C "$work" checkout -b "feature/new-branch-no-new-commits" -q "$sha"

set +e
git -C "$work" push -u origin HEAD -q
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  eprint "FAIL: expected push to succeed when the new branch contains no new commits"
  exit 1
fi

printf '%s\n' "OK: pre-push does not gate when new branch has no new commits"
