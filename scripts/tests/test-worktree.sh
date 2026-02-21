#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

worktree_sh_src="$repo_root/scripts/worktree.sh"
extractor_src="$repo_root/scripts/extract-issue-files.py"

if [[ ! -x "$worktree_sh_src" ]]; then
  eprint "Missing script or not executable: $worktree_sh_src"
  exit 1
fi

if [[ ! -f "$extractor_src" ]]; then
  eprint "Missing extractor: $extractor_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-worktree-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q

mkdir -p "$tmpdir/scripts"
cp -p "$worktree_sh_src" "$tmpdir/scripts/worktree.sh"
cp -p "$extractor_src" "$tmpdir/scripts/extract-issue-files.py"
chmod +x "$tmpdir/scripts/worktree.sh"

# Stub gh for deterministic tests (no network/auth)
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal stub for:
#   gh issue view <n> --json body
#   gh issue develop --list <n>
#   gh issue develop <n> --name <branch>
#   gh -R OWNER/REPO issue view <n> --json body

repo=""
if [[ ${1:-} == "-R" ]]; then
  repo="${2:-}"
  shift 2
fi

if [[ ${1:-} != "issue" ]]; then
  echo "unsupported" >&2
  exit 2
fi

sub="${2:-}"
case "$sub" in
  view)
    issue="${3:-}"
    body=""
    case "$issue" in
      1)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/a.ts`\n- [ ] `src/shared.ts`\n'
        ;;
      2)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/b.ts`\n- [ ] `src/shared.ts`\n'
        ;;
      *)
        body=$'## 概要\n\nfrom gh\n\n### 変更対象ファイル（推定）\n\n- [ ] `src/other.ts`\n'
        ;;
    esac

    printf '{"body":%s}\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<<"$body")"
    ;;
  develop)
    shift 2

    list=0
    name=""
    issue=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -l|--list)
          list=1
          shift
          ;;
        -n|--name)
          name="${2:-}"
          shift 2
          ;;
        -b|--base)
          # ignored
          shift 2
          ;;
        -c|--checkout)
          # ignored
          shift
          ;;
        *)
          issue="$1"
          shift
          ;;
      esac
    done

    if [[ -z "$issue" ]]; then
      echo "missing issue" >&2
      exit 2
    fi

    state_file="$(dirname "$0")/gh_issue_develop_state"
    if [[ "$list" -eq 1 ]]; then
      if [[ -f "$state_file" ]]; then
        awk -v issue="$issue" '$1 == issue {print $2}' "$state_file"
      fi
      exit 0
    fi

    if [[ -z "$name" ]]; then
      echo "missing --name" >&2
      exit 2
    fi

    if [[ -f "$state_file" ]] && awk -v issue="$issue" '$1 == issue {found=1} END{exit found?0:1}' "$state_file"; then
      echo "issue already has linked branch" >&2
      exit 1
    fi

    echo "$issue $name" >> "$state_file"
    if ! git show-ref --verify --quiet "refs/heads/$name"; then
      git branch "$name" HEAD
    fi
    exit 0
    ;;
  *)
    echo "unsupported" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$tmpdir/bin/gh"

# Minimal content
cat > "$tmpdir/README.md" <<'EOF'
# Temp Repo
EOF

git -C "$tmpdir" add README.md
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q

# Issue body fixtures
cat > "$tmpdir/issue-1.md" <<'EOF'
## 概要

test

### 変更対象ファイル（推定）

- [ ] `src/a.ts`
- [ ] `src/shared.ts`
EOF

cat > "$tmpdir/issue-2.md" <<'EOF'
## 概要

test

### 変更対象ファイル（推定）

- [ ] `src/b.ts`
- [ ] `src/shared.ts`
EOF

cat > "$tmpdir/issue-3.md" <<'EOF'
## 概要

test

### 変更対象ファイル（推定）

- [ ] `src/c.ts`
EOF

# Issue JSON fixtures (same shape as `gh issue view --json body`)
python3 -c 'import json,sys; print(json.dumps({"body": sys.stdin.read()}))' \
  < "$tmpdir/issue-1.md" > "$tmpdir/issue-1.json"

python3 -c 'import json,sys; print(json.dumps({"body": sys.stdin.read()}))' \
  < "$tmpdir/issue-2.md" > "$tmpdir/issue-2.json"

mkdir -p "$tmpdir/src"
touch "$tmpdir/src/a.ts" "$tmpdir/src/b.ts" "$tmpdir/src/c.ts" "$tmpdir/src/shared.ts"

git -C "$tmpdir" add issue-1.md issue-2.md issue-3.md issue-1.json issue-2.json src
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "add fixtures" -q

cat > "$tmpdir/scripts/sync-agent-config.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> .sync-agent-config.log
EOF
chmod +x "$tmpdir/scripts/sync-agent-config.sh"
git -C "$tmpdir" add scripts/sync-agent-config.sh
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "add sync stub" -q

# Extractor: local file
out1="$(python3 "$tmpdir/scripts/extract-issue-files.py" --repo-root "$tmpdir" --issue-body-file "$tmpdir/issue-1.md" --mode section)"
if ! printf '%s\n' "$out1" | grep -qx "src/a.ts"; then
  eprint "Expected src/a.ts in extracted files"
  exit 1
fi

# Extractor: JSON body file (compat: allow `gh issue view --json body` output passed as --issue-body-file)
out1_json="$(python3 "$tmpdir/scripts/extract-issue-files.py" --repo-root "$tmpdir" --issue-body-file "$tmpdir/issue-1.json" --mode section)"
if ! printf '%s\n' "$out1_json" | grep -qx "src/shared.ts"; then
  eprint "Expected src/shared.ts in extracted files from JSON body file"
  exit 1
fi

# Extractor: gh issue view path (stub)
out_gh="$(PATH="$tmpdir/bin:$PATH" python3 "$tmpdir/scripts/extract-issue-files.py" --repo-root "$tmpdir" --issue 1 --mode section)"
if ! printf '%s\n' "$out_gh" | grep -qx "src/shared.ts"; then
  eprint "Expected src/shared.ts in extracted files via gh"
  exit 1
fi

# worktree.sh check: conflict via gh (stub)
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh check --issue 1 --issue 2) >/dev/null 2>"$tmpdir/stderr-gh"
code_gh=$?
set -e

if [[ "$code_gh" -ne 3 ]]; then
  eprint "Expected exit code 3 for gh conflict, got: $code_gh"
  cat "$tmpdir/stderr-gh" >&2
  exit 1
fi

if ! grep -q "src/shared.ts" "$tmpdir/stderr-gh"; then
  eprint "Expected shared file in gh conflict output"
  cat "$tmpdir/stderr-gh" >&2
  exit 1
fi

# worktree.sh check: no conflict
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh check --issue 1 --issue 3) >/dev/null

(cd "$tmpdir" && ./scripts/worktree.sh bootstrap --tool opencode) >/dev/null
if [[ ! -f "$tmpdir/.sync-agent-config.log" ]]; then
  eprint "Expected bootstrap to run sync-agent-config.sh"
  exit 1
fi
if ! grep -q -- "--force opencode" "$tmpdir/.sync-agent-config.log"; then
  eprint "Expected bootstrap sync invocation args in log"
  cat "$tmpdir/.sync-agent-config.log" >&2
  exit 1
fi

# worktree.sh new/remove (Issue lock enabled by default; gh is stubbed)
worktrees_root="$tmpdir/wt"
wt_dir="$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh new --issue 99 --desc "parallel test" --base HEAD --tool none --worktrees-root "$worktrees_root")"

if [[ ! -d "$wt_dir" ]]; then
  eprint "Expected worktree dir to exist: $wt_dir"
  exit 1
fi


(cd "$tmpdir" && ./scripts/worktree.sh remove --dir "$wt_dir")

# Creating the same Issue again should fail unless --use-existing-branch is set
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh new --issue 99 --desc "parallel test" --base HEAD --tool none --worktrees-root "$worktrees_root") >/dev/null 2>"$tmpdir/stderr-issue-lock"
code_lock=$?
set -e

if [[ "$code_lock" -eq 0 ]]; then
  eprint "Expected failure due to existing Issue lock"
  exit 1
fi

if ! grep -q "already has linked branch" "$tmpdir/stderr-issue-lock" && ! grep -q "linked branch" "$tmpdir/stderr-issue-lock"; then
  eprint "Expected Issue lock error message, got:"
  cat "$tmpdir/stderr-issue-lock" >&2
  exit 1
fi

# Recreate worktree from the linked branch (no --desc required)
wt_dir2="$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh new --issue 99 --use-existing-branch --tool none --worktrees-root "$worktrees_root")"

if [[ ! -d "$wt_dir2" ]]; then
  eprint "Expected worktree dir to exist: $wt_dir2"
  exit 1
fi

(cd "$tmpdir" && ./scripts/worktree.sh remove --dir "$wt_dir2")

wt_dir3="$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/worktree.sh new --issue 100 --desc "sync fallback" --base HEAD --tool opencode --worktrees-root "$worktrees_root")"
if [[ ! -f "$wt_dir3/.sync-agent-config.log" ]]; then
  eprint "Expected new --tool opencode to run sync-agent-config.sh in worktree"
  exit 1
fi
if ! grep -q -- "--force opencode" "$wt_dir3/.sync-agent-config.log"; then
  eprint "Expected worktree sync invocation args in log"
  cat "$wt_dir3/.sync-agent-config.log" >&2
  exit 1
fi

rm -f "$wt_dir3/.sync-agent-config.log"

(cd "$tmpdir" && ./scripts/worktree.sh remove --dir "$wt_dir3")

eprint "OK: scripts/tests/test-worktree.sh"
