#!/usr/bin/env bash

# install-agentic-sdd.sh
#
# Install Agentic-SDD workflow files into an existing project directory.
#
# This script is meant to be run from a cloned Agentic-SDD repository.

set -euo pipefail

usage() {
    cat << 'EOF'
Usage: install-agentic-sdd.sh --target <dir> [options]

    Options:
      --target <dir>            Target project directory (required)
      --mode minimal|full       What to install (default: minimal)
      --tool none|opencode|codex|claude|all
                                Run sync for the selected tool (default: none)
      --ci none|github-actions  Optional CI template to install (default: none)
      --shogun-ops              Optional: install Shogun Ops (checkin/collect/supervise + ops scripts)
      --force                   Overwrite conflicting files (backs up first)
      --dry-run                 Show what would change
      -h, --help                Show help

Exit codes:
  0  Success
  2  Conflicts found (re-run with --force)
EOF
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

MODE="minimal"
TOOL="none"
CI="none"
SHOGUN_OPS=false
FORCE=false
DRY_RUN=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_DIR="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --tool)
            TOOL="$2"
            shift 2
            ;;
        --ci)
            CI="$2"
            shift 2
            ;;
        --shogun-ops)
            SHOGUN_OPS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    log_error "--target is required"
    usage
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    log_error "Target directory does not exist: $TARGET_DIR"
    exit 1
fi

case "$MODE" in
    minimal|full) ;;
    *)
        log_error "Invalid --mode: $MODE (expected minimal|full)"
        exit 1
        ;;
esac

case "$TOOL" in
    none|opencode|codex|claude|all) ;;
    *)
        log_error "Invalid --tool: $TOOL (expected none|opencode|codex|claude|all)"
        exit 1
        ;;
esac

case "$CI" in
    none|github-actions) ;;
    *)
        log_error "Invalid --ci: $CI (expected none|github-actions)"
        exit 1
        ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
TARGET_DIR=$(cd -- "$TARGET_DIR" && pwd)

if [ ! -d "$SOURCE_ROOT/.agent" ]; then
    log_error "This does not look like Agentic-SDD repo root: $SOURCE_ROOT (.agent/ missing)"
    exit 1
fi

timestamp() { date +%Y%m%d_%H%M%S; }

copied=0
skipped=0
conflicts=0
declare -a conflict_paths=()

scan_conflict_file() {
    local src="$1"
    local dst="$2"

    [ -f "$src" ] || return 0
    [ -e "$dst" ] || return 0

    if cmp -s "$src" "$dst"; then
        return 0
    fi

    conflict_paths+=("$dst")
    ((conflicts+=1))
}

scan_conflict_dir() {
    local src_dir="$1"
    local dst_dir="$2"

    [ -d "$src_dir" ] || return 0

    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        scan_conflict_file "$src_dir/$rel" "$dst_dir/$rel"
    done < <(cd "$src_dir" && find . -type f -print0)
}

should_exclude_rel() {
    local rel="$1"
    shift
    local pat
    for pat in "$@"; do
        if [[ "$rel" == $pat ]]; then
            return 0
        fi
    done
    return 1
}

scan_conflict_dir_excluding() {
    local src_dir="$1"
    local dst_dir="$2"
    shift 2
    local -a exclude_pats=("$@")

    [ -d "$src_dir" ] || return 0

    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        if should_exclude_rel "$rel" "${exclude_pats[@]}"; then
            continue
        fi
        scan_conflict_file "$src_dir/$rel" "$dst_dir/$rel"
    done < <(cd "$src_dir" && find . -type f -print0)
}

backup_path() {
    local path="$1"
    local ts
    ts=$(timestamp)
    echo "${path}.bak.${ts}"
}

copy_file() {
    local src="$1"
    local dst="$2"

    if [ ! -f "$src" ]; then
        log_warn "Skip missing source file: $src"
        return 0
    fi

    local dst_dir
    dst_dir=$(dirname "$dst")

    if [ "$DRY_RUN" = true ]; then
        if [ -e "$dst" ]; then
            if cmp -s "$src" "$dst"; then
                log_info "[DRY-RUN] identical: $dst"
            else
                if [ "$FORCE" = true ]; then
                    log_info "[DRY-RUN] overwrite: $dst (backup: $(backup_path "$dst"))"
                else
                    log_warn "[DRY-RUN] conflict: $dst"
                fi
            fi
        else
            log_info "[DRY-RUN] create: $dst"
        fi
        return 0
    fi

    mkdir -p "$dst_dir"

    if [ -e "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            ((skipped+=1))
            return 0
        fi

        if [ "$FORCE" = true ]; then
            local backup
            backup=$(backup_path "$dst")
            mv "$dst" "$backup"
            cp -p "$src" "$dst"
            ((copied+=1))
            return 0
        fi

        conflict_paths+=("$dst")
        ((conflicts+=1))
        return 0
    fi

    cp -p "$src" "$dst"
    ((copied+=1))
}

copy_dir() {
    local src_dir="$1"
    local dst_dir="$2"

    if [ ! -d "$src_dir" ]; then
        log_warn "Skip missing source dir: $src_dir"
        return 0
    fi

    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        copy_file "$src_dir/$rel" "$dst_dir/$rel"
    done < <(cd "$src_dir" && find . -type f -print0)
}

copy_dir_excluding() {
    local src_dir="$1"
    local dst_dir="$2"
    shift 2
    local -a exclude_pats=("$@")

    if [ ! -d "$src_dir" ]; then
        log_warn "Skip missing source dir: $src_dir"
        return 0
    fi

    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        if should_exclude_rel "$rel" "${exclude_pats[@]}"; then
            continue
        fi
        copy_file "$src_dir/$rel" "$dst_dir/$rel"
    done < <(cd "$src_dir" && find . -type f -print0)
}

ensure_gitignore_line() {
    local gitignore="$1"
    local line="$2"

    if [ -f "$gitignore" ] && grep -Fqx "$line" "$gitignore"; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] append to $gitignore: $line"
        return 0
    fi

    mkdir -p "$(dirname "$gitignore")"
    touch "$gitignore"
    printf '%s\n' "$line" >> "$gitignore"
}

log_info "Installing Agentic-SDD into: $TARGET_DIR"
log_info "Mode: $MODE, Tool: $TOOL, CI: $CI, Shogun Ops: $SHOGUN_OPS, Force: $FORCE, Dry-run: $DRY_RUN"

agent_excludes=(
    "commands/checkin.md"
    "commands/collect.md"
    "commands/supervise.md"
    "commands/status.md"
    "commands/refactor-draft.md"
    "commands/refactor-issue.md"
)

scripts_excludes=(
    "shogun-ops.py"
    "shogun-*.sh"
    "tmux"
    "tests/test-shogun-*.sh"
)

# Fail-fast conflict scan (avoid partial installs when not using --force)
if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    if [ "$SHOGUN_OPS" = true ]; then
        scan_conflict_dir "$SOURCE_ROOT/.agent" "$TARGET_DIR/.agent"
    else
        scan_conflict_dir_excluding "$SOURCE_ROOT/.agent" "$TARGET_DIR/.agent" "${agent_excludes[@]}"
    fi
    scan_conflict_file "$SOURCE_ROOT/docs/prd/_template.md" "$TARGET_DIR/docs/prd/_template.md"
    scan_conflict_file "$SOURCE_ROOT/docs/epics/_template.md" "$TARGET_DIR/docs/epics/_template.md"
    scan_conflict_file "$SOURCE_ROOT/docs/decisions.md" "$TARGET_DIR/docs/decisions.md"
    scan_conflict_file "$SOURCE_ROOT/docs/glossary.md" "$TARGET_DIR/docs/glossary.md"
    scan_conflict_dir "$SOURCE_ROOT/skills" "$TARGET_DIR/skills"
    if [ "$SHOGUN_OPS" = true ]; then
        scan_conflict_dir "$SOURCE_ROOT/scripts" "$TARGET_DIR/scripts"
    else
        scan_conflict_dir_excluding "$SOURCE_ROOT/scripts" "$TARGET_DIR/scripts" "${scripts_excludes[@]}"
    fi
    scan_conflict_dir "$SOURCE_ROOT/templates/project-config" "$TARGET_DIR/templates/project-config"
    scan_conflict_file "$SOURCE_ROOT/requirements-agentic-sdd.txt" "$TARGET_DIR/requirements-agentic-sdd.txt"
    scan_conflict_dir "$SOURCE_ROOT/.githooks" "$TARGET_DIR/.githooks"

    if [ "$TOOL" = "claude" ] || [ "$TOOL" = "all" ]; then
        scan_conflict_file "$SOURCE_ROOT/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
    fi

    if [ "$MODE" = "full" ]; then
        scan_conflict_dir "$SOURCE_ROOT/.github" "$TARGET_DIR/.github"
    fi

    if [ "$CI" = "github-actions" ]; then
        scan_conflict_dir "$SOURCE_ROOT/templates/ci/github-actions/.github/workflows" "$TARGET_DIR/.github/workflows"
        scan_conflict_file "$SOURCE_ROOT/templates/ci/github-actions/scripts/agentic-sdd-ci.sh" "$TARGET_DIR/scripts/agentic-sdd-ci.sh"
    fi

    # AGENTS.md (do not overwrite; use append file when target already has AGENTS.md)
    if [ -f "$TARGET_DIR/AGENTS.md" ]; then
        scan_conflict_file "$SOURCE_ROOT/AGENTS.md" "$TARGET_DIR/AGENTS.md.agentic-sdd.append.md"
    else
        scan_conflict_file "$SOURCE_ROOT/AGENTS.md" "$TARGET_DIR/AGENTS.md"
    fi

    if [ "$conflicts" -gt 0 ]; then
        log_error "Conflicts found: $conflicts"
        for p in "${conflict_paths[@]}"; do
            log_error "  - $p"
        done
        log_error "Re-run with --force to overwrite (backups will be created)."
        exit 2
    fi

    # Reset counters before real copy (scan_conflict_* shares the same counters)
    conflicts=0
    conflict_paths=()
fi

# Core workflow files
if [ "$SHOGUN_OPS" = true ]; then
    copy_dir "$SOURCE_ROOT/.agent" "$TARGET_DIR/.agent"
else
    copy_dir_excluding "$SOURCE_ROOT/.agent" "$TARGET_DIR/.agent" "${agent_excludes[@]}"
fi

# Docs templates (only the required files)
copy_file "$SOURCE_ROOT/docs/prd/_template.md" "$TARGET_DIR/docs/prd/_template.md"
copy_file "$SOURCE_ROOT/docs/epics/_template.md" "$TARGET_DIR/docs/epics/_template.md"
copy_file "$SOURCE_ROOT/docs/decisions.md" "$TARGET_DIR/docs/decisions.md"
copy_file "$SOURCE_ROOT/docs/glossary.md" "$TARGET_DIR/docs/glossary.md"

# Design skills
copy_dir "$SOURCE_ROOT/skills" "$TARGET_DIR/skills"

# Scripts
if [ "$SHOGUN_OPS" = true ]; then
    copy_dir "$SOURCE_ROOT/scripts" "$TARGET_DIR/scripts"
else
    copy_dir_excluding "$SOURCE_ROOT/scripts" "$TARGET_DIR/scripts" "${scripts_excludes[@]}"
fi

# Templates (for /generate-project-config command)
copy_dir "$SOURCE_ROOT/templates/project-config" "$TARGET_DIR/templates/project-config"

# Python dependencies (for scripts like generate-project-config.py)
copy_file "$SOURCE_ROOT/requirements-agentic-sdd.txt" "$TARGET_DIR/requirements-agentic-sdd.txt"

# Git hooks (tool-agnostic final defense line)
copy_dir "$SOURCE_ROOT/.githooks" "$TARGET_DIR/.githooks"

# Claude Code hooks (optional)
if [ "$TOOL" = "claude" ] || [ "$TOOL" = "all" ]; then
    copy_file "$SOURCE_ROOT/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
fi

# GitHub templates (optional)
if [ "$MODE" = "full" ]; then
    # Copy issue/PR templates only. Workflows in this repo are for Agentic-SDD itself.
    copy_file "$SOURCE_ROOT/.github/PULL_REQUEST_TEMPLATE.md" "$TARGET_DIR/.github/PULL_REQUEST_TEMPLATE.md"
    copy_dir "$SOURCE_ROOT/.github/ISSUE_TEMPLATE" "$TARGET_DIR/.github/ISSUE_TEMPLATE"
fi

# CI templates (optional)
if [ "$CI" = "github-actions" ]; then
    copy_dir "$SOURCE_ROOT/templates/ci/github-actions/.github/workflows" "$TARGET_DIR/.github/workflows"
    copy_file "$SOURCE_ROOT/templates/ci/github-actions/scripts/agentic-sdd-ci.sh" "$TARGET_DIR/scripts/agentic-sdd-ci.sh"
fi

# AGENTS.md
if [ -f "$TARGET_DIR/AGENTS.md" ]; then
    log_warn "AGENTS.md already exists; writing append file instead"
    copy_file "$SOURCE_ROOT/AGENTS.md" "$TARGET_DIR/AGENTS.md.agentic-sdd.append.md"
else
    copy_file "$SOURCE_ROOT/AGENTS.md" "$TARGET_DIR/AGENTS.md"
fi

# .gitignore updates
ensure_gitignore_line "$TARGET_DIR/.gitignore" "# Agentic-SDD"
ensure_gitignore_line "$TARGET_DIR/.gitignore" ".agent/agents/*.local.md"
ensure_gitignore_line "$TARGET_DIR/.gitignore" ".claude/settings.local.json"
ensure_gitignore_line "$TARGET_DIR/.gitignore" ".agentic-sdd/"
ensure_gitignore_line "$TARGET_DIR/.gitignore" ".opencode/"
ensure_gitignore_line "$TARGET_DIR/.gitignore" ".codex/"

# Git hooks activation (local config)
if [ "$DRY_RUN" = false ]; then
    if command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [ -x "$TARGET_DIR/scripts/setup-githooks.sh" ]; then
            log_info "Configuring git hooks (core.hooksPath=.githooks)"
            if [ "$FORCE" = true ]; then
                (cd "$TARGET_DIR" && ./scripts/setup-githooks.sh --force --quiet)
            else
                (cd "$TARGET_DIR" && ./scripts/setup-githooks.sh --quiet)
            fi
        else
            log_warn "Missing executable: $TARGET_DIR/scripts/setup-githooks.sh (skipping hooks setup)"
        fi
    else
        log_warn "Target is not a git repo; skipping hooks setup"
    fi
fi

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] done"
    exit 0
fi

# Conflicts should already be handled by the pre-scan above.
# Keep this check as a safety net for race conditions.
if [ "$conflicts" -gt 0 ] && [ "$FORCE" = false ]; then
    log_error "Conflicts found: $conflicts"
    for p in "${conflict_paths[@]}"; do
        log_error "  - $p"
    done
    log_error "Re-run with --force to overwrite (backups will be created)."
    exit 2
fi

log_info "Installed files: $copied, Skipped identical: $skipped, Conflicts: $conflicts"

# Tool-specific sync
if [ "$TOOL" != "none" ] && [ "$TOOL" != "claude" ]; then
    if [ ! -x "$TARGET_DIR/scripts/sync-agent-config.sh" ]; then
        log_error "Missing executable: $TARGET_DIR/scripts/sync-agent-config.sh"
        exit 1
    fi

    log_info "Running sync-agent-config.sh for: $TOOL"
    (cd "$TARGET_DIR" && ./scripts/sync-agent-config.sh --force "$TOOL")
fi

log_info "Done."
