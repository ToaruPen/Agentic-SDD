#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update-agentic-sdd.sh [options]

Update Agentic-SDD files managed via git subtree.

Options:
  --prefix <path>      Subtree prefix in the target repo (default: .agentic-sdd)
  --repo <url>         Upstream repository URL
                       (default: https://github.com/ToaruPen/Agentic-SDD.git)
  --ref <ref>          Upstream ref to pull (tag/branch/sha). Required unless AGENTIC_SDD_SUBTREE_REF is set.
  --dry-run            Print the git subtree command without executing it
  -h, --help           Show this help

Environment:
  AGENTIC_SDD_SUBTREE_PREFIX
  AGENTIC_SDD_SUBTREE_REPO
  AGENTIC_SDD_SUBTREE_REF

Examples:
  ./scripts/update-agentic-sdd.sh --ref v0.2.39
  ./scripts/update-agentic-sdd.sh --prefix .agentic-sdd --repo https://github.com/ToaruPen/Agentic-SDD.git --ref main
EOF
}

log_info() { printf '[INFO] %s\n' "$*"; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

PREFIX="${AGENTIC_SDD_SUBTREE_PREFIX:-.agentic-sdd}"
REPO="${AGENTIC_SDD_SUBTREE_REPO:-https://github.com/ToaruPen/Agentic-SDD.git}"
REF="${AGENTIC_SDD_SUBTREE_REF:-}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        log_error "Missing value for --prefix"
        usage
        exit 1
      fi
      PREFIX="$2"
      shift 2
      ;;
    --repo)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        log_error "Missing value for --repo"
        usage
        exit 1
      fi
      REPO="$2"
      shift 2
      ;;
    --ref)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        log_error "Missing value for --ref"
        usage
        exit 1
      fi
      REF="$2"
      shift 2
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

if [[ -z "$REF" ]]; then
  log_error "--ref is required (or set AGENTIC_SDD_SUBTREE_REF)"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  log_error "git command not found"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_error "Current directory is not inside a git repository"
  exit 1
fi

if [[ ! -d "$PREFIX" ]]; then
  log_error "Prefix directory does not exist: $PREFIX"
  log_error "Run initial import first: git subtree add --prefix=$PREFIX $REPO $REF --squash"
  exit 1
fi

cmd=(git subtree pull --prefix "$PREFIX" "$REPO" "$REF" --squash)

log_info "prefix=$PREFIX"
log_info "repo=$REPO"
log_info "ref=$REF"

if [[ ! -x "$(git --exec-path)/git-subtree" ]]; then
  log_error "git subtree is not available in this environment"
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[DRY-RUN]'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
log_info "Subtree update completed"
