#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_src="$repo_root/scripts/create-pr.sh"

if [[ ! -x "$script_src" ]]; then
  eprint "Missing script or not executable: $script_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-create-pr-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

origin_bare="$tmpdir/origin.git"
git init -q --bare "$origin_bare"

work="$tmpdir/work"
mkdir -p "$work"
git -C "$work" init -q
git -C "$work" remote add origin "$origin_bare"

cat > "$work/README.md" <<'EOF'
# Temp Repo
EOF

git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "init" -q
git -C "$work" branch -M main
git -C "$work" push -u origin main -q

git -C "$work" checkout -b feature/issue-1-test -q
echo "change" >> "$work/README.md"
git -C "$work" add README.md
git -C "$work" -c user.name=test -c user.email=test@example.com commit -m "feat: change" -q

# review-cycle fixture
mkdir -p "$work/.agentic-sdd/reviews/issue-1/run1"
printf '%s' 'run1' > "$work/.agentic-sdd/reviews/issue-1/.current_run"
cat > "$work/.agentic-sdd/reviews/issue-1/run1/review.json" <<'EOF'
{
  "schema_version": 3,
  "scope_id": "issue-1",
  "status": "Approved",
  "findings": [],
  "questions": [],
  "overall_explanation": "ok"
}
EOF

# Stub gh (no network/auth)
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="$(dirname "$0")"
pr_state="$state_dir/pr_state"

if [[ ${1:-} == "auth" && ${2:-} == "status" ]]; then
  exit 0
fi

if [[ ${1:-} == "issue" && ${2:-} == "develop" && ${3:-} == "--list" ]]; then
  issue="${4:-}"
  if [[ "$issue" == "1" ]]; then
    printf '%s\n' "feature/issue-1-test"
    exit 0
  fi
  exit 0
fi

if [[ ${1:-} == "issue" && ${2:-} == "view" ]]; then
  issue="${3:-}"
  # We ignore --json args in this stub.
  if [[ "$issue" == "1" ]]; then
    printf '{"title":"Issue 1 title","url":"https://example.invalid/issues/1"}\n'
    exit 0
  fi
  printf '{"title":"Issue %s"}\n' "$issue"
  exit 0
fi

if [[ ${1:-} == "pr" && ${2:-} == "list" ]]; then
  # gh pr list --head <branch> --state all --json ...
  if [[ -f "$pr_state" ]]; then
    cat "$pr_state"
  else
    printf '[]\n'
  fi
  exit 0
fi

if [[ ${1:-} == "pr" && ${2:-} == "create" ]]; then
  # Return URL and persist state
  url="https://example.invalid/pull/1"
  printf '[{"number":1,"url":"%s","state":"OPEN"}]\n' "$url" > "$pr_state"
  printf '%s\n' "$url"
  exit 0
fi

echo "unsupported gh invocation" >&2
exit 2
EOF
chmod +x "$tmpdir/bin/gh"

(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --dry-run --issue 1) >/dev/null 2>/dev/null

out="$(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --issue 1 2>/dev/null)"
if [[ "$out" != "https://example.invalid/pull/1" ]]; then
  eprint "Expected PR URL, got: $out"
  exit 1
fi

# Second run should reuse existing PR (same URL)
out2="$(cd "$work" && PATH="$tmpdir/bin:$PATH" "$script_src" --issue 1 2>/dev/null)"
if [[ "$out2" != "https://example.invalid/pull/1" ]]; then
  eprint "Expected existing PR URL, got: $out2"
  exit 1
fi

eprint "OK: scripts/tests/test-create-pr.sh"
