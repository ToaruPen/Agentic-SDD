#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cleanup_sh_src="$repo_root/scripts/cleanup.sh"

if [[ ! -x "$cleanup_sh_src" ]]; then
  eprint "Missing script or not executable: $cleanup_sh_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-cleanup-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q

mkdir -p "$tmpdir/scripts"
cp -p "$cleanup_sh_src" "$tmpdir/scripts/cleanup.sh"
chmod +x "$tmpdir/scripts/cleanup.sh"

cat > "$tmpdir/README.md" <<'EOF'
# Temp Repo
EOF
git -C "$tmpdir" add README.md
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q

# Ensure the base branch is always named 'main' to avoid environment-dependent
# init.defaultBranch (e.g. master) breaking 'git switch main' below.
git -C "$tmpdir" branch -M main

# Case 1: worktree無しでも issue-<n> ブランチを削除できる
branch1="feature/issue-123-test"
git -C "$tmpdir" switch -c "$branch1" -q
printf 'x\n' >> "$tmpdir/README.md"
git -C "$tmpdir" add README.md
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "change" -q
git -C "$tmpdir" switch main -q
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com merge --no-ff "$branch1" -m "merge $branch1" -q

if ! git -C "$tmpdir" show-ref --verify --quiet "refs/heads/$branch1"; then
  eprint "Expected local branch to exist before cleanup: $branch1"
  exit 1
fi

# dry-run は削除しない
(cd "$tmpdir" && ./scripts/cleanup.sh 123 --dry-run) >/dev/null
if ! git -C "$tmpdir" show-ref --verify --quiet "refs/heads/$branch1"; then
  eprint "dry-run unexpectedly deleted branch: $branch1"
  exit 1
fi

(cd "$tmpdir" && ./scripts/cleanup.sh 123) >/dev/null
if git -C "$tmpdir" show-ref --verify --quiet "refs/heads/$branch1"; then
  eprint "Expected local branch to be deleted: $branch1"
  exit 1
fi

# Case 2: worktree ディレクトリが消えていても --all で掃除できる（porcelain パース + remove）
branch2="feature/issue-124-stale-worktree"
wt_path="$tmpdir/wt-issue-124"
git -C "$tmpdir" worktree add -b "$branch2" "$wt_path" -q
printf 'y\n' >> "$wt_path/README.md"
git -C "$wt_path" add README.md
git -C "$wt_path" -c user.name=test -c user.email=test@example.com commit -m "worktree change" -q
git -C "$tmpdir" switch main -q
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com merge --no-ff "$branch2" -m "merge $branch2" -q

rm -rf "$wt_path"

(cd "$tmpdir" && ./scripts/cleanup.sh --all) >/dev/null
if git -C "$tmpdir" show-ref --verify --quiet "refs/heads/$branch2"; then
  eprint "Expected merged branch to be deleted by --all: $branch2"
  exit 1
fi

eprint "OK"
