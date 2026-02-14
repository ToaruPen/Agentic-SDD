#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/worktree.sh <command> [args]

Deterministic helper for parallel development with git worktrees.

Commands:
  new        Create a worktree + branch for an Issue
  bootstrap  Generate tool configs in an existing worktree
  check      Detect overlaps between Issues by declared change-target files
  list       List worktrees
  remove     Remove a worktree

Examples:
  ./scripts/worktree.sh check --issue 123 --issue 124
  ./scripts/worktree.sh new --issue 123 --desc "add user profile" --tool opencode
  ./scripts/worktree.sh remove --dir ../.worktrees/myrepo/issue-123-add-user-profile

EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    eprint "Missing command: $cmd"
    exit 1
  fi
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

main_repo_root_from_common_dir() {
  local root="$1"
  local common
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common" && "$(basename "$common")" == ".git" ]]; then
    dirname "$common"
    return 0
  fi
  printf '%s\n' "$root"
}

default_worktrees_root() {
  local root="$1"
  local main_root
  main_root="$(main_repo_root_from_common_dir "$root")"
  local repo_name
  repo_name="$(basename "$main_root")"
  printf '%s\n' "$(dirname "$main_root")/.worktrees/$repo_name"
}

slugify() {
  local s="$1"
  # Lowercase and keep [a-z0-9], collapse other sequences into '-'
  printf '%s' "$s" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -cs 'a-z0-9' '-' \
    | sed -e 's/^-\+//' -e 's/-\+$//'
}

branch_exists() {
  local branch="$1"
  git show-ref --verify --quiet "refs/heads/$branch"
}

cmd_list() {
  git worktree list
}

cmd_bootstrap() {
  local dir=""
  local tool=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        dir="$2"; shift 2 ;;
      --tool)
        tool="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: scripts/worktree.sh bootstrap [--dir <path>] --tool <opencode|codex|all>

Generate tool configs in a worktree directory.
EOF
        exit 0
        ;;
      *)
        eprint "Unknown arg: $1"; exit 2 ;;
    esac
  done

  if [[ -z "$tool" ]]; then
    eprint "--tool is required (opencode|codex|all)"
    exit 2
  fi

  if [[ -z "$dir" ]]; then
    dir="$(repo_root)"
  fi

  if [[ ! -d "$dir" ]]; then
    eprint "Directory not found: $dir"
    exit 2
  fi

  if [[ ! -x "$dir/scripts/sync-agent-config.sh" ]]; then
    eprint "Missing executable: $dir/scripts/sync-agent-config.sh"
    exit 1
  fi

  (cd "$dir" && ./scripts/sync-agent-config.sh --force "$tool")
}

cmd_new() {
  local issue=""
  local desc=""
  local type="feature"
  local base="main"
  local branch=""
  local dir=""
  local worktrees_root=""
  local tool="${AGENTIC_SDD_WORKTREE_TOOL:-}"
  local use_existing_branch=0
  local lock_issue="${AGENTIC_SDD_WORKTREE_LOCK_ISSUE:-1}"

  case "$lock_issue" in
    0|1) ;;
    *) lock_issue=1 ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue)
        issue="$2"; shift 2 ;;
      --desc)
        desc="$2"; shift 2 ;;
      --type)
        type="$2"; shift 2 ;;
      --base)
        base="$2"; shift 2 ;;
      --branch)
        branch="$2"; shift 2 ;;
      --dir)
        dir="$2"; shift 2 ;;
      --worktrees-root)
        worktrees_root="$2"; shift 2 ;;
      --tool)
        tool="$2"; shift 2 ;;
      --use-existing-branch)
        use_existing_branch=1; shift ;;
      --lock-issue)
        lock_issue=1; shift ;;
      --no-lock-issue)
        lock_issue=0; shift ;;
      -h|--help)
        cat <<'EOF'
 Usage: scripts/worktree.sh new --issue <number> [--desc <short description>] [options]

Options:
  --branch <name>         Explicit branch name (skips --type/--desc naming)
  --type <type>           feature|fix|docs|refactor|test|chore (default: feature)
  --desc <text>           Used to build branch name when --branch is omitted
  --base <ref>            Start point (default: main)
  --dir <path>            Worktree directory (default: computed under --worktrees-root)
   --worktrees-root <dir>  Root directory for worktrees (default: ../.worktrees/<repo>)
   --tool <none|opencode|codex|all>
                           Run sync-agent-config in the new worktree (default: env or opencode)
   --use-existing-branch   Allow reusing an existing linked/local branch (default: fail)
   --lock-issue            Create a linked branch on the Issue via `gh issue develop` (default)
   --no-lock-issue         Skip Issue lock/linking (offline / local-only)

 Notes:
   - Branch naming rules: .agent/rules/branch.md
EOF
        exit 0
        ;;
      *)
        eprint "Unknown arg: $1"; exit 2 ;;
    esac
  done

  if [[ -z "$issue" ]]; then
    eprint "--issue is required"
    exit 2
  fi

  local root
  root="$(repo_root)"
  if [[ -z "$root" ]]; then
    eprint "Not in a git repository."
    exit 1
  fi

  if [[ -z "$worktrees_root" ]]; then
    worktrees_root="$(default_worktrees_root "$root")"
  fi

  if [[ -z "$tool" ]]; then
    tool="opencode"
  fi
  case "$tool" in
    none|opencode|codex|all) ;;
    *) eprint "Invalid --tool: $tool (expected none|opencode|codex|all)"; exit 2 ;;
  esac

  # If Issue locking is enabled, treat linked branches as the SoT for "in progress".
  # This is fail-fast: by default, do not create a new worktree if the Issue already has
  # any linked branch.
  declare -a linked_branches=()
  if [[ "$lock_issue" -eq 1 && "$issue" =~ ^[0-9]+$ ]]; then
    require_cmd gh

    local list_out
    if ! list_out="$(gh issue develop --list "$issue" 2>&1)"; then
      eprint "Failed to list linked branches for Issue #$issue:"
      eprint "$list_out"
      exit 1
    fi

    while IFS= read -r line; do
      for token in $line; do
        token="${token#-}"
        token="${token#,}"
        token="${token%:}"
        token="${token%\`}"; token="${token#\`}"
        token="${token%\"}"; token="${token#\"}"
        if git check-ref-format --branch "$token" >/dev/null 2>&1; then
          linked_branches+=("$token")
        fi
      done
    done <<<"$list_out"
  fi

  # Reuse an existing linked branch (resume/recreate worktree).
  if [[ "${#linked_branches[@]}" -gt 0 ]]; then
    if [[ "$use_existing_branch" -ne 1 ]]; then
      eprint "Issue #$issue already has linked branch(es):"
      for b in "${linked_branches[@]}"; do
        eprint "  - $b"
      done
      eprint "Re-run with --use-existing-branch to reuse."
      exit 2
    fi

    if [[ -n "$branch" ]]; then
      found=0
      for b in "${linked_branches[@]}"; do
        if [[ "$b" == "$branch" ]]; then
          found=1
          break
        fi
      done
      if [[ "$found" -ne 1 ]]; then
        eprint "--branch is not a linked branch for Issue #$issue: $branch"
        eprint "Linked branches:"
        for b in "${linked_branches[@]}"; do
          eprint "  - $b"
        done
        exit 2
      fi
    else
      if [[ "${#linked_branches[@]}" -eq 1 ]]; then
        branch="${linked_branches[0]}"
      else
        eprint "Issue #$issue has multiple linked branches; specify --branch."
        eprint "Linked branches:"
        for b in "${linked_branches[@]}"; do
          eprint "  - $b"
        done
        exit 2
      fi
    fi

    if [[ -z "$dir" ]]; then
      dir="$worktrees_root/$(printf '%s' "$branch" | tr '/' '-')"
    fi

    if [[ -e "$dir" ]]; then
      eprint "Worktree path already exists: $dir"
      exit 2
    fi

    mkdir -p "$(dirname "$dir")"

    if ! branch_exists "$branch"; then
      remote="origin"
      if ! git remote get-url "$remote" >/dev/null 2>&1; then
        eprint "Remote '$remote' not found; cannot fetch linked branch: $branch"
        eprint "Create the branch locally or re-run with --no-lock-issue."
        exit 1
      fi
      if ! git fetch "$remote" "$branch:refs/heads/$branch" 1>&2; then
        eprint "Failed to fetch linked branch from '$remote': $branch"
        exit 1
      fi
    fi

    git worktree add "$dir" "$branch" 1>&2

    if [[ "$tool" != "none" ]]; then
      if [[ ! -x "$dir/scripts/sync-agent-config.sh" ]]; then
        eprint "Warning: sync-agent-config.sh not found/executable in new worktree: $dir"
      else
        (cd "$dir" && ./scripts/sync-agent-config.sh --force "$tool") 1>&2
      fi
    fi

    printf '%s\n' "$dir"
    return 0
  fi

  if [[ -z "$branch" ]]; then
    if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
      eprint "--branch is required when --issue is not numeric: $issue"
      exit 2
    fi
    if [[ -z "$desc" ]]; then
      eprint "--desc is required when --branch is omitted"
      exit 2
    fi
    case "$type" in
      feature|fix|docs|refactor|test|chore) ;;
      *) eprint "Invalid --type: $type"; exit 2 ;;
    esac
    local slug
    slug="$(slugify "$desc")"
    if [[ -z "$slug" ]]; then
      eprint "Failed to build slug from --desc"
      exit 2
    fi
    branch="$type/issue-$issue-$slug"
    if [[ -z "$dir" ]]; then
      dir="$worktrees_root/issue-$issue-$slug"
    fi
  else
    if [[ -z "$dir" ]]; then
      dir="$worktrees_root/$(printf '%s' "$branch" | tr '/' '-')"
    fi
  fi

  if [[ -e "$dir" ]]; then
    eprint "Worktree path already exists: $dir"
    exit 2
  fi

  mkdir -p "$(dirname "$dir")"

  if [[ "$lock_issue" -eq 1 && "$issue" =~ ^[0-9]+$ ]]; then
    local develop_out
    if ! develop_out="$(gh issue develop "$issue" --name "$branch" 2>&1)"; then
      eprint "Failed to create a linked branch for Issue #$issue:"
      eprint "$develop_out"
      exit 1
    fi

    if ! branch_exists "$branch"; then
      remote="origin"
      if ! git remote get-url "$remote" >/dev/null 2>&1; then
        eprint "Remote '$remote' not found; cannot fetch linked branch: $branch"
        eprint "Re-run with --no-lock-issue to skip Issue locking."
        exit 1
      fi
      if ! git fetch "$remote" "$branch:refs/heads/$branch" 1>&2; then
        eprint "Failed to fetch linked branch from '$remote': $branch"
        exit 1
      fi
    fi

    git worktree add "$dir" "$branch" 1>&2
  else
    if branch_exists "$branch"; then
      if [[ "$use_existing_branch" -ne 1 ]]; then
        eprint "Branch already exists: $branch"
        eprint "If you want to use it, re-run with --use-existing-branch"
        exit 2
      fi
      git worktree add "$dir" "$branch" 1>&2
    else
      git worktree add "$dir" -b "$branch" "$base" 1>&2
    fi
  fi

  if [[ "$tool" != "none" ]]; then
    if [[ ! -x "$dir/scripts/sync-agent-config.sh" ]]; then
      eprint "Warning: sync-agent-config.sh not found/executable in new worktree: $dir"
    else
      (cd "$dir" && ./scripts/sync-agent-config.sh --force "$tool") 1>&2
    fi
  fi

  printf '%s\n' "$dir"
}

cmd_remove() {
  local dir=""
  local force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        dir="$2"; shift 2 ;;
      --force)
        force=1; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: scripts/worktree.sh remove --dir <path> [--force]

Remove a worktree.
EOF
        exit 0
        ;;
      *)
        eprint "Unknown arg: $1"; exit 2 ;;
    esac
  done

  if [[ -z "$dir" ]]; then
    eprint "--dir is required"
    exit 2
  fi

  if [[ "$force" -eq 1 ]]; then
    git worktree remove --force "$dir"
  else
    git worktree remove "$dir"
  fi
}

cmd_check() {
  local gh_repo=""
  local mode="section"
  declare -a issues=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue)
        issues+=("$2"); shift 2 ;;
      --gh-repo)
        gh_repo="$2"; shift 2 ;;
      --mode)
        mode="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: scripts/worktree.sh check [--gh-repo OWNER/REPO] [--mode section|anywhere] \
  --issue <n>...

Detect overlaps between Issues by declared change-target files.

Exit codes:
  0: no overlap
  2: invalid input / cannot extract change targets
  3: overlaps found
EOF
        exit 0
        ;;
      *)
        eprint "Unknown arg: $1"; exit 2 ;;
    esac
  done

  if [[ "${#issues[@]}" -eq 0 ]]; then
    eprint "At least one --issue is required"
    exit 2
  fi

  local root
  root="$(repo_root)"
  if [[ -z "$root" ]]; then
    eprint "Not in a git repository."
    exit 1
  fi

  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  local extractor="$script_dir/extract-issue-files.py"
  if [[ ! -f "$extractor" ]]; then
    eprint "Missing extractor: $extractor"
    exit 1
  fi

  if [[ "$mode" != "section" && "$mode" != "anywhere" ]]; then
    eprint "Invalid --mode: $mode (expected section|anywhere)"
    exit 2
  fi

  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-worktree)"
  cleanup() { rm -rf "$tmpdir"; }
  trap cleanup EXIT

  declare -a keys=()
  declare -a filesets=()

  idx=0
  if [[ "${#issues[@]}" -gt 0 ]]; then
    for n in "${issues[@]}"; do
      key="issue:$n"
      out_file="$tmpdir/set.$idx"
      if ! python3 "$extractor" --repo-root "$root" --issue "$n" --gh-repo "$gh_repo" --mode "$mode" >"$out_file" 2>"$tmpdir/err.$idx"; then
        eprint "Failed to extract files for $key:"
        cat "$tmpdir/err.$idx" >&2
        exit 2
      fi
      sort -u "$out_file" >"$out_file.sorted" && mv "$out_file.sorted" "$out_file"
      keys+=("$key")
      filesets+=("$out_file")
      idx=$((idx+1))
    done
  fi

  conflicts=0
  for ((i=0; i<${#keys[@]}; i++)); do
    for ((j=i+1; j<${#keys[@]}; j++)); do
      overlap="$(comm -12 "${filesets[$i]}" "${filesets[$j]}" || true)"
      if [[ -n "$overlap" ]]; then
        conflicts=$((conflicts+1))
        eprint "CONFLICT: ${keys[$i]} <-> ${keys[$j]}"
        eprint "Overlapping files:"
        printf '%s\n' "$overlap" >&2
        eprint ""
      fi
    done
  done

  if [[ "$conflicts" -gt 0 ]]; then
    eprint "Found overlaps: $conflicts"
    exit 3
  fi

  printf '%s\n' "OK: no overlaps"
}

main() {
  require_cmd git
  require_cmd python3

  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  cmd="$1"
  shift
  case "$cmd" in
    -h|--help|help)
      usage
      ;;
    list)
      cmd_list "$@"
      ;;
    bootstrap)
      cmd_bootstrap "$@"
      ;;
    new)
      cmd_new "$@"
      ;;
    remove)
      cmd_remove "$@"
      ;;
    check)
      cmd_check "$@"
      ;;
    *)
      eprint "Unknown command: $cmd"
      usage
      exit 2
      ;;
  esac
}

main "$@"
