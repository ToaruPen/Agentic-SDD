#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: setup-global-agentic-sdd.sh [--dry-run]

Install global entrypoints for Agentic-SDD (safe, with backups).

Installs:
  - ~/.local/bin/agentic-sdd
  - ~/.config/agentic-sdd/default-ref (auto-detected)
  - ~/.config/agentic-sdd/repo
  - OpenCode command: ~/.config/opencode/commands/agentic-sdd.md
  - OpenCode skill: ~/.config/opencode/skills/agentic-sdd (symlink to ~/.codex/skills/agentic-sdd)
  - Codex skill: ~/.codex/skills/agentic-sdd/SKILL.md
  - Codex skill changelog: ~/.codex/skills/agentic-sdd/CHANGELOG.md
  - Claude skill: ~/.claude/skills/agentic-sdd/SKILL.md

Options:
  --dry-run    Show planned changes only
  -h, --help   Show help
EOF
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

timestamp() { date +%Y%m%d_%H%M%S; }

backup_path() {
    local path="$1"
    echo "${path}.bak.$(timestamp)"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Missing command: $cmd"
        exit 1
    fi
}

write_file() {
    local dst="$1"
    local content="$2"
    local dry_run="$3"

    local dst_dir
    dst_dir="$(dirname "$dst")"

    if [ -f "$dst" ] && [ "$(cat "$dst" 2>/dev/null || true)" = "$content" ]; then
        if [ "$dry_run" = true ]; then
            log_info "[DRY-RUN] identical: $dst"
        fi
        return 0
    fi

    if [ "$dry_run" = true ]; then
        if [ -f "$dst" ]; then
            log_info "[DRY-RUN] overwrite: $dst (backup: $(backup_path "$dst"))"
        else
            log_info "[DRY-RUN] create: $dst"
        fi
        return 0
    fi

    mkdir -p "$dst_dir"

    if [ -f "$dst" ]; then
        local backup
        backup="$(backup_path "$dst")"
        mv "$dst" "$backup"
    fi

    printf '%s\n' "$content" > "$dst"
}

copy_with_backup() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"

    if [ ! -f "$src" ]; then
        log_error "Missing source file: $src"
        exit 1
    fi

    local dst_dir
    dst_dir="$(dirname "$dst")"

    if [ "$dry_run" = true ]; then
        if [ -e "$dst" ]; then
            if cmp -s "$src" "$dst"; then
                log_info "[DRY-RUN] identical: $dst"
            else
                log_info "[DRY-RUN] overwrite: $dst (backup: $(backup_path "$dst"))"
            fi
        else
            log_info "[DRY-RUN] create: $dst"
        fi
        return 0
    fi

    mkdir -p "$dst_dir"

    if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
        local backup
        backup="$(backup_path "$dst")"
        mv "$dst" "$backup"
    fi

    cp -p "$src" "$dst"
}

ensure_symlink_with_backup() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"

    if [ ! -e "$src" ]; then
        log_error "Missing symlink source: $src"
        exit 1
    fi

    local dst_dir
    dst_dir="$(dirname "$dst")"

    if [ -L "$dst" ]; then
        local target
        target="$(readlink "$dst" 2>/dev/null || true)"
        if [ "$target" = "$src" ]; then
            if [ "$dry_run" = true ]; then
                log_info "[DRY-RUN] identical symlink: $dst"
            fi
            return 0
        fi
    fi

    if [ "$dry_run" = true ]; then
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            log_info "[DRY-RUN] overwrite: $dst (backup: $(backup_path "$dst"))"
        else
            log_info "[DRY-RUN] create: $dst"
        fi
        log_info "[DRY-RUN] ln -s: $src -> $dst"
        return 0
    fi

    mkdir -p "$dst_dir"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$(backup_path "$dst")"
    fi

    ln -s "$src" "$dst"
}

ensure_executable() {
    local path="$1"
    local dry_run="$2"

    if [ "$dry_run" = true ]; then
        log_info "[DRY-RUN] chmod +x: $path"
        return 0
    fi

    chmod +x "$path"
}

detect_remote_default_ref() {
    local url="$1"
    local symref
    local ssh_cmd="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}"
    if ! symref="$(GIT_SSH_COMMAND="$ssh_cmd" git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 ls-remote --symref "$url" HEAD 2>/dev/null | awk '/^ref:/ {print $2; exit}')"; then
        return 1
    fi
    if [[ "$symref" =~ ^refs/heads/(.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
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

require_cmd git

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$SOURCE_ROOT/.agent" ]; then
    log_error "This does not look like Agentic-SDD repo root: $SOURCE_ROOT (.agent/ missing)"
    exit 1
fi

repo_sha="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
repo_url="${AGENTIC_SDD_REPO:-https://github.com/ToaruPen/Agentic-SDD.git}"
if [ -n "${AGENTIC_SDD_DEFAULT_REF:-}" ]; then
    default_ref="$AGENTIC_SDD_DEFAULT_REF"
else
    if ! default_ref="$(detect_remote_default_ref "$repo_url")"; then
        log_error "Could not detect default branch from repo URL: $repo_url"
        log_error "Set AGENTIC_SDD_DEFAULT_REF explicitly and rerun setup-global-agentic-sdd.sh"
        exit 1
    fi
fi

log_info "Installing global Agentic-SDD entrypoints"
log_info "Repo SHA: $repo_sha"
log_info "Repo URL: $repo_url"
log_info "Default ref: $default_ref"

home="$HOME"

# 1) Helper CLI
copy_with_backup "$SOURCE_ROOT/scripts/agentic-sdd" "$home/.local/bin/agentic-sdd" "$DRY_RUN"
ensure_executable "$home/.local/bin/agentic-sdd" "$DRY_RUN"

# 2) Pinned defaults
write_file "$home/.config/agentic-sdd/default-ref" "$default_ref" "$DRY_RUN"
write_file "$home/.config/agentic-sdd/repo" "$repo_url" "$DRY_RUN"

# 3) OpenCode command
copy_with_backup \
    "$SOURCE_ROOT/templates/opencode/commands/agentic-sdd.md" \
    "$home/.config/opencode/commands/agentic-sdd.md" \
    "$DRY_RUN"

# 4) Codex skill
copy_with_backup \
    "$SOURCE_ROOT/templates/codex/skills/agentic-sdd/SKILL.md" \
    "$home/.codex/skills/agentic-sdd/SKILL.md" \
    "$DRY_RUN"

# 4.0) Codex skill changelog
copy_with_backup \
    "$SOURCE_ROOT/CHANGELOG.md" \
    "$home/.codex/skills/agentic-sdd/CHANGELOG.md" \
    "$DRY_RUN"

# 4.1) OpenCode skill (symlink to the Codex skill)
ensure_symlink_with_backup \
    "$home/.codex/skills/agentic-sdd" \
    "$home/.config/opencode/skills/agentic-sdd" \
    "$DRY_RUN"

# 5) Claude skill
copy_with_backup \
    "$SOURCE_ROOT/templates/claude/skills/agentic-sdd/SKILL.md" \
    "$home/.claude/skills/agentic-sdd/SKILL.md" \
    "$DRY_RUN"

log_info "Done."
