#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/scripts/install-agentic-sdd.sh"

if [[ ! -x "$installer" ]]; then
  eprint "Missing script or not executable: $installer"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-install-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

mkproj() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q

  cat > "$dir/README.md" <<'EOF'
# Temp Repo
EOF

  git -C "$dir" add README.md
  git -C "$dir" -c user.name=test -c user.email=test@example.com commit -m "init" -q
}

# 1) Conflict detection should fail-fast with exit code 2
proj1="$tmpdir/proj1"
mkproj "$proj1"

mkdir -p "$proj1/.agent/commands"
cat > "$proj1/.agent/commands/init.md" <<'EOF'
conflict
EOF

set +e
"$installer" --target "$proj1" --mode minimal --tool none >/dev/null 2>"$tmpdir/stderr-conflict"
code=$?
set -e

if [[ "$code" -ne 2 ]]; then
  eprint "Expected exit code 2 for conflicts, got: $code"
  cat "$tmpdir/stderr-conflict" >&2
  exit 1
fi

if [[ -e "$proj1/docs/prd/_template.md" ]]; then
  eprint "Did not expect partial install on conflict (docs/prd/_template.md exists)"
  exit 1
fi

# 2) Minimal install + OpenCode sync + existing AGENTS.md should create append file
proj2="$tmpdir/proj2"
mkproj "$proj2"

cat > "$proj2/AGENTS.md" <<'EOF'
# Existing AGENTS

do not overwrite
EOF

cp -p "$proj2/AGENTS.md" "$tmpdir/AGENTS.before"

"$installer" --target "$proj2" --mode minimal --tool opencode >/dev/null

if [[ ! -d "$proj2/.agent" ]]; then
  eprint "Expected .agent/ to be installed"
  exit 1
fi

if [[ -f "$proj2/.agent/commands/checkin.md" ]]; then
  eprint "Did not expect Shogun Ops command doc to be installed by default: .agent/commands/checkin.md"
  exit 1
fi

if [[ -e "$proj2/scripts/shogun-ops.py" ]]; then
  eprint "Did not expect Shogun Ops script to be installed by default: scripts/shogun-ops.py"
  exit 1
fi

if ! cmp -s "$proj2/AGENTS.md" "$tmpdir/AGENTS.before"; then
  eprint "Expected AGENTS.md to remain unchanged"
  exit 1
fi

if [[ ! -f "$proj2/AGENTS.md.agentic-sdd.append.md" ]]; then
  eprint "Expected append file to be created: AGENTS.md.agentic-sdd.append.md"
  exit 1
fi

if [[ ! -f "$proj2/.opencode/commands/sdd-init.md" ]]; then
  eprint "Expected OpenCode command to exist: .opencode/commands/sdd-init.md"
  exit 1
fi

if [[ ! -f "$proj2/.opencode/commands/create-pr.md" ]]; then
  eprint "Expected OpenCode command to exist: .opencode/commands/create-pr.md"
  exit 1
fi

if [[ -f "$proj2/.opencode/commands/checkin.md" ]]; then
  eprint "Did not expect Shogun Ops OpenCode command to be installed by default: .opencode/commands/checkin.md"
  exit 1
fi

if [[ -f "$proj2/.opencode/commands/init.md" ]]; then
  eprint "Did not expect OpenCode init override: .opencode/commands/init.md"
  exit 1
fi

if [[ -e "$proj2/.github/PULL_REQUEST_TEMPLATE.md" ]]; then
  eprint "Did not expect GitHub templates in mode=minimal"
  exit 1
fi

# .gitignore entries should exist and not duplicate
if [[ ! -f "$proj2/.gitignore" ]]; then
  eprint "Expected .gitignore to be created"
  exit 1
fi

if ! grep -Fqx ".agentic-sdd/" "$proj2/.gitignore"; then
  eprint "Expected .gitignore to include .agentic-sdd/"
  exit 1
fi

"$installer" --target "$proj2" --mode minimal --tool none >/dev/null

count="$(grep -Fxc ".agentic-sdd/" "$proj2/.gitignore" || true)"
if [[ "$count" -ne 1 ]]; then
  eprint "Expected .gitignore to contain exactly one '.agentic-sdd/' line, got: $count"
  exit 1
fi

# 3) Full mode should install GitHub templates (but not workflows)
proj3="$tmpdir/proj3"
mkproj "$proj3"

"$installer" --target "$proj3" --mode full --tool none >/dev/null

if [[ ! -f "$proj3/.github/PULL_REQUEST_TEMPLATE.md" ]]; then
  eprint "Expected PR template to be installed in mode=full"
  exit 1
fi

if [[ ! -f "$proj3/.github/ISSUE_TEMPLATE/feature.md" ]]; then
  eprint "Expected issue template to be installed in mode=full"
  exit 1
fi

if [[ -d "$proj3/.github/workflows" ]]; then
  eprint "Did not expect workflows to be installed"
  exit 1
fi

# 4) Opt-in CI templates should install workflows + script (and not include Agentic-SDD internal workflows)
proj4="$tmpdir/proj4"
mkproj "$proj4"

"$installer" --target "$proj4" --mode minimal --tool none --ci github-actions >/dev/null

if [[ ! -f "$proj4/.github/workflows/agentic-sdd-ci.yml" ]]; then
  eprint "Expected CI workflow to be installed: .github/workflows/agentic-sdd-ci.yml"
  exit 1
fi

if [[ ! -f "$proj4/scripts/agentic-sdd-ci.sh" ]]; then
  eprint "Expected CI script to be installed: scripts/agentic-sdd-ci.sh"
  exit 1
fi

if [[ -f "$proj4/.github/workflows/release.yml" ]]; then
  eprint "Did not expect Agentic-SDD internal workflow to be installed: .github/workflows/release.yml"
  exit 1
fi

# 5) Opt-in Shogun Ops should install ops scripts + commands
proj5="$tmpdir/proj5"
mkproj "$proj5"

"$installer" --target "$proj5" --mode minimal --tool opencode --shogun-ops >/dev/null

if [[ ! -f "$proj5/scripts/shogun-ops.py" ]]; then
  eprint "Expected Shogun Ops script to be installed with --shogun-ops: scripts/shogun-ops.py"
  exit 1
fi

if [[ ! -f "$proj5/scripts/shogun-tmux.sh" ]]; then
  eprint "Expected Shogun Ops script to be installed with --shogun-ops: scripts/shogun-tmux.sh"
  exit 1
fi

if [[ ! -f "$proj5/.agent/commands/checkin.md" ]]; then
  eprint "Expected Shogun Ops command doc to be installed with --shogun-ops: .agent/commands/checkin.md"
  exit 1
fi

if [[ ! -f "$proj5/.opencode/commands/checkin.md" ]]; then
  eprint "Expected Shogun Ops OpenCode command to exist with --shogun-ops: .opencode/commands/checkin.md"
  exit 1
fi

eprint "OK: scripts/tests/test-install-agentic-sdd.sh"
