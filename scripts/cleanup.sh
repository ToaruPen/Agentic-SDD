#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/cleanup.sh [issue-number | --all] [options]

Clean up worktree + local branch after merge.

Arguments:
  issue-number      Issue number to clean up (e.g., 123)
  --all             Clean up all merged worktrees + branches

Options:
  --dry-run             Show what would be deleted (no actual deletion)
  --force               Force delete even with uncommitted changes
  --skip-merge-check    Skip merge status verification
  --keep-local-branch   Delete worktree only, keep local branch

Examples:
  ./scripts/cleanup.sh 123                    # Clean up Issue #123
  ./scripts/cleanup.sh 123 --dry-run          # Preview cleanup
  ./scripts/cleanup.sh --all                  # Clean up all merged worktrees
  ./scripts/cleanup.sh --all --dry-run        # Preview all cleanups

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

is_branch_merged() {
  local branch="$1"
  local base="${2:-main}"

  # Check if branch is merged into base
  if git branch --merged "$base" --format='%(refname:short)' 2>/dev/null | grep -Fxq "$branch"; then
    return 0
  fi

  # Also check if branch was merged via squash/rebase by checking if PR is merged
  if command -v gh >/dev/null 2>&1; then
    local pr_state
    pr_state="$(gh pr list --head "$branch" --state merged --json number --jq 'length' 2>/dev/null || echo "0")"
    if [[ "$pr_state" -gt 0 ]]; then
      return 0
    fi
  fi

  return 1
}

has_uncommitted_changes() {
  local worktree_path="$1"
  if [[ ! -d "$worktree_path" ]]; then
    return 1
  fi

  # Check for uncommitted changes in the worktree
  if ! git -C "$worktree_path" diff --quiet 2>/dev/null; then
    return 0
  fi
  if ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
    return 0
  fi

  return 1
}

list_worktrees_with_branch() {
  # Output: <worktree_path>\t<branch_name>
  # branch_name is empty for detached HEAD worktrees.
  git worktree list --porcelain | awk '
    $1=="worktree" {
      $1=""
      sub(/^ /,"")
      path=$0
      branch=""
      next
    }
    $1=="branch" {
      b=$2
      sub("^refs/heads/","",b)
      branch=b
      next
    }
    /^$/ {
      if (path != "") { printf "%s\t%s\n", path, branch }
      path=""; branch=""
      next
    }
    END {
      if (path != "") { printf "%s\t%s\n", path, branch }
    }
  '
}

find_worktree_entry_for_issue() {
  local issue="$1"
  local root="$2"

  while IFS=$'\t' read -r wt_path branch; do
    # Skip main repo
    if [[ "$wt_path" == "$root" ]]; then
      continue
    fi

    if [[ "$wt_path" =~ issue-$issue(-|$) ]] || [[ -n "$branch" && "$branch" =~ issue-$issue(-|$) ]]; then
      printf '%s\t%s\n' "$wt_path" "$branch"
      return 0
    fi
  done < <(list_worktrees_with_branch)

  return 1
}

list_merged_worktrees() {
  local root="$1"
  local base="${2:-main}"

  while IFS=$'\t' read -r wt_path branch; do
    # Skip main repo
    if [[ "$wt_path" == "$root" ]]; then
      continue
    fi

    if [[ -z "$branch" ]]; then
      continue
    fi

    # Skip main/master branches
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
      continue
    fi

    if is_branch_merged "$branch" "$base"; then
      printf '%s\t%s\n' "$wt_path" "$branch"
    fi
  done < <(list_worktrees_with_branch)
}

find_local_branches_for_issue() {
  local issue="$1"
  while IFS= read -r branch; do
    if [[ "$branch" =~ (^|/)issue-${issue}(-|$) ]]; then
      printf '%s\n' "$branch"
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)
}

find_worktree_for_branch() {
  local target_branch="$1"
  local root="$2"

  while IFS=$'\t' read -r wt_path branch; do
    if [[ "$wt_path" == "$root" ]]; then
      continue
    fi
    if [[ -n "$branch" && "$branch" == "$target_branch" ]]; then
      printf '%s\n' "$wt_path"
      return 0
    fi
  done < <(list_worktrees_with_branch)

  return 1
}

cleanup_branch_only() {
  local branch="$1"
  local dry_run="$2"
  local skip_merge_check="$3"
  local keep_local_branch="$4"
  local force="$5"
  local base="${6:-main}"

  if [[ "$keep_local_branch" -eq 1 ]]; then
    eprint "Keeping local branch as requested: $branch"
    return 0
  fi

  # Safety check: merge status
  if [[ "$skip_merge_check" -ne 1 ]]; then
    if ! is_branch_merged "$branch" "$base"; then
      eprint "Warning: branch '$branch' is not merged into '$base'"
      eprint "  Use --skip-merge-check to force cleanup"
      return 1
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    eprint "[dry-run] Would delete local branch: $branch"
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    if [[ "$force" -eq 1 ]]; then
      git branch -D "$branch" || return 1
    else
      git branch -d "$branch" || return 1
    fi
    eprint "Deleted local branch: $branch"
  fi

  return 0
}

cleanup_single() {
  local wt_path="$1"
  local branch="$2"
  local dry_run="$3"
  local force="$4"
  local skip_merge_check="$5"
  local keep_local_branch="$6"
  local base="${7:-main}"

  # Safety check: merge status
  if [[ "$skip_merge_check" -ne 1 ]]; then
    if ! is_branch_merged "$branch" "$base"; then
      eprint "Warning: branch '$branch' is not merged into '$base'"
      eprint "  Use --skip-merge-check to force cleanup"
      return 1
    fi
  fi

  # Safety check: uncommitted changes
  if [[ -d "$wt_path" ]] && has_uncommitted_changes "$wt_path"; then
    if [[ "$force" -ne 1 ]]; then
      eprint "Warning: worktree '$wt_path' has uncommitted changes"
      eprint "  Use --force to delete anyway"
      return 1
    fi
    eprint "Warning: forcing deletion despite uncommitted changes"
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    if [[ -n "$wt_path" ]]; then
      eprint "[dry-run] Would remove worktree: $wt_path"
    fi
    if [[ "$keep_local_branch" -ne 1 ]]; then
      eprint "[dry-run] Would delete local branch: $branch"
    fi
    return 0
  fi

  # Remove worktree
  if [[ -n "$wt_path" ]]; then
    if [[ "$force" -eq 1 ]]; then
      git worktree remove --force "$wt_path" || return 1
    else
      git worktree remove "$wt_path" || return 1
    fi
    eprint "Removed worktree: $wt_path"
  fi

  # Delete local branch
  if [[ "$keep_local_branch" -ne 1 ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      if [[ "$force" -eq 1 ]]; then
        git branch -D "$branch" || return 1
      else
        git branch -d "$branch" || return 1
      fi
      eprint "Deleted local branch: $branch"
    fi
  fi

  return 0
}

main() {
  require_cmd git

  local issue=""
  local all_mode=0
  local dry_run=0
  local force=0
  local skip_merge_check=0
  local keep_local_branch=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        all_mode=1; shift ;;
      --dry-run)
        dry_run=1; shift ;;
      --force)
        force=1; shift ;;
      --skip-merge-check)
        skip_merge_check=1; shift ;;
      --keep-local-branch)
        keep_local_branch=1; shift ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        eprint "Unknown option: $1"
        usage
        exit 2
        ;;
      *)
        if [[ -z "$issue" ]]; then
          issue="$1"
        else
          eprint "Unexpected argument: $1"
          usage
          exit 2
        fi
        shift
        ;;
    esac
  done

  # Validate arguments
  if [[ "$all_mode" -eq 1 && -n "$issue" ]]; then
    eprint "Cannot specify both --all and issue number"
    exit 2
  fi

  if [[ "$all_mode" -eq 0 && -z "$issue" ]]; then
    eprint "Either issue number or --all is required"
    usage
    exit 2
  fi

  local root
  root="$(repo_root)"
  if [[ -z "$root" ]]; then
    eprint "Not in a git repository."
    exit 1
  fi

  # Get main repo root (in case we're in a worktree)
  local main_root
  main_root="$(main_repo_root_from_common_dir "$root")"

  local success_count=0
  local fail_count=0

  if [[ "$all_mode" -eq 1 ]]; then
    # Clean up all merged worktrees
    local found=0
    while IFS=$'\t' read -r wt_path branch; do
      found=1
      if cleanup_single "$wt_path" "$branch" "$dry_run" "$force" "$skip_merge_check" "$keep_local_branch"; then
        ((success_count++)) || true
      else
        ((fail_count++)) || true
      fi
    done < <(list_merged_worktrees "$main_root")

    if [[ "$found" -eq 0 ]]; then
      eprint "No merged worktrees found."
      exit 0
    fi
  else
    # Clean up single issue
    if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
      eprint "Invalid issue number: $issue"
      exit 2
    fi

    local wt_entry
    wt_entry="$(find_worktree_entry_for_issue "$issue" "$main_root" || true)"

    if [[ -z "$wt_entry" ]]; then
      local branches=()
      while IFS= read -r b; do
        branches+=("$b")
      done < <(find_local_branches_for_issue "$issue" || true)

      if [[ "${#branches[@]}" -eq 0 ]]; then
        printf '%s\n' "No worktree found for Issue #$issue" >&2
        exit 1
      fi

      if [[ "${#branches[@]}" -gt 1 ]]; then
        eprint "Multiple local branches match Issue #$issue:"
        for b in "${branches[@]}"; do
          eprint "  - $b"
        done
        eprint "Delete them manually or narrow the match."
        exit 1
      fi

      local branch="${branches[0]}"
      local wt_for_branch
      wt_for_branch="$(find_worktree_for_branch "$branch" "$main_root" || true)"

      if [[ -n "$wt_for_branch" ]]; then
        if cleanup_single "$wt_for_branch" "$branch" "$dry_run" "$force" "$skip_merge_check" "$keep_local_branch"; then
          ((success_count++)) || true
        else
          ((fail_count++)) || true
        fi
      else
        if cleanup_branch_only "$branch" "$dry_run" "$skip_merge_check" "$keep_local_branch" "$force"; then
          ((success_count++)) || true
        else
          ((fail_count++)) || true
        fi
      fi
    else
      local wt_path branch
      IFS=$'\t' read -r wt_path branch <<<"$wt_entry"

      if [[ -z "$branch" ]]; then
        eprint "Could not determine branch for worktree: $wt_path"
        exit 1
      fi

      if cleanup_single "$wt_path" "$branch" "$dry_run" "$force" "$skip_merge_check" "$keep_local_branch"; then
        ((success_count++)) || true
      else
        ((fail_count++)) || true
      fi
    fi
  fi

  # Report
  eprint ""
  if [[ "$dry_run" -eq 1 ]]; then
    eprint "=== Dry-run complete ==="
    eprint "Would clean up: $success_count worktree(s)"
    if [[ "$fail_count" -gt 0 ]]; then
      eprint "Skipped due to warnings: $fail_count worktree(s)"
    fi
  else
    eprint "=== Cleanup complete ==="
    eprint "Cleaned up: $success_count worktree(s)"
    if [[ "$fail_count" -gt 0 ]]; then
      eprint "Failed: $fail_count worktree(s)"
      exit 1
    fi
  fi
}

main "$@"
