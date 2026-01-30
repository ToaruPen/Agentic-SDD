#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/shogun-watcher.sh [--dry-run] [--once]

Watch Agentic-SDD Shogun Ops checkin queue and run `collect` automatically.

Options:
  --dry-run   Print the selected watch tool and the commands that would run.
  --once      Exit after the first detected event triggers a collect (test-friendly).
  -h, --help  Show this help.

Notes:
  - This script requires a file watch tool: fswatch | watchexec | inotifywait
  - Ops data lives under: <git-common-dir>/agentic-sdd-ops/
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
ONCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --once)
      ONCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      eprint "Unknown arg: $1"
      usage >&2
      exit 2
      ;;
  esac
done

# Select a watch tool (AC3: fail-fast with actionable next steps).
WATCH_TOOL=""
if command -v fswatch >/dev/null 2>&1; then
  WATCH_TOOL="fswatch"
elif command -v watchexec >/dev/null 2>&1; then
  WATCH_TOOL="watchexec"
elif command -v inotifywait >/dev/null 2>&1; then
  WATCH_TOOL="inotifywait"
else
  eprint "No supported watch tool found (fswatch|watchexec|inotifywait)."
  eprint "Next actions:"
  eprint "  - macOS (recommended): brew install fswatch"
  eprint "  - Alternative (macOS/Linux): brew install watchexec"
  eprint "  - Debian/Ubuntu: sudo apt-get install inotify-tools"
  exit 1
fi

# Resolve git common dir -> ops checkins dir.
if ! abs_git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)"; then
  eprint "Not a git repository (git rev-parse failed)."
  exit 1
fi

common_abs=""
if common_abs="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  :
else
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "$common_dir" ]]; then
    eprint "Failed to resolve git common dir."
    exit 1
  fi
  if [[ "$common_dir" == ".git" || "$common_dir" == "./.git" ]]; then
    common_abs="$abs_git_dir"
  elif [[ "$common_dir" = /* ]]; then
    common_abs="$common_dir"
  else
    common_abs="$abs_git_dir/$common_dir"
  fi
  # Normalize
  common_abs="$(cd -- "$common_abs" && pwd -P)"
fi

ops_root="$common_abs/agentic-sdd-ops"
checkins_dir="$ops_root/queue/checkins"

collect_cmd=(python3 "$SCRIPT_DIR/shogun-ops.py" collect)

watch_cmd_str=""
case "$WATCH_TOOL" in
  fswatch)
    watch_cmd_str="fswatch -r '$checkins_dir'"
    ;;
  watchexec)
    watch_cmd_str="watchexec -w '$checkins_dir' -- python3 '$SCRIPT_DIR/shogun-ops.py' collect"
    ;;
  inotifywait)
    watch_cmd_str="inotifywait -m -e create -e moved_to -r '$checkins_dir'"
    ;;
  *)
    eprint "Internal error: unknown WATCH_TOOL=$WATCH_TOOL"
    exit 1
    ;;
esac

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'watch_tool=%s\n' "$WATCH_TOOL"
  printf 'watch_dir=%s\n' "$checkins_dir"
  printf 'watch_cmd=%s\n' "$watch_cmd_str"
  printf 'collect_cmd=%s\n' "${collect_cmd[*]}"
  exit 0
fi

# Ensure ops layout exists (creates checkins_dir).
python3 "$SCRIPT_DIR/shogun-ops.py" status >/dev/null

case "$WATCH_TOOL" in
  fswatch)
    mkdir -p "$checkins_dir"
    while IFS= read -r _event; do
      rc=0
      if "${collect_cmd[@]}"; then
        rc=0
      else
        rc=$?
        eprint "collect failed (exit=$rc)"
      fi
      if [[ "$ONCE" -eq 1 ]]; then
        exit "$rc"
      fi
    done < <(fswatch -r "$checkins_dir")
    ;;

  inotifywait)
    mkdir -p "$checkins_dir"
    while IFS= read -r _event; do
      rc=0
      if "${collect_cmd[@]}"; then
        rc=0
      else
        rc=$?
        eprint "collect failed (exit=$rc)"
      fi
      if [[ "$ONCE" -eq 1 ]]; then
        exit "$rc"
      fi
    done < <(inotifywait -m -e create -e moved_to -r "$checkins_dir" 2>/dev/null)
    ;;

  watchexec)
    mkdir -p "$checkins_dir"
    once_flag=()
    if [[ "$ONCE" -eq 1 ]]; then
      if watchexec --help 2>&1 | grep -q -- "--once"; then
        once_flag=(--once)
      fi
    fi
    exec watchexec "${once_flag[@]}" -w "$checkins_dir" -- "${collect_cmd[@]}"
    ;;

  *)
    eprint "Internal error: unknown WATCH_TOOL=$WATCH_TOOL"
    exit 1
    ;;
esac
