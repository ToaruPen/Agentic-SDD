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
RUN_COLLECT_ONLY=0

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
    --run-collect)
      # Internal: used as a watchexec target command.
      RUN_COLLECT_ONLY=1
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
  common_abs="$(cd -- "$common_abs" && pwd -P)"
fi

ops_root="$common_abs/agentic-sdd-ops"
checkins_dir="$ops_root/queue/checkins"
lock_path="$ops_root/locks/collect.lock"

collect_cmd=(python3 "$SCRIPT_DIR/shogun-ops.py" collect)

queue_has_pending_checkins() {
  find "$checkins_dir" -type f -name '*.yaml' -print -quit 2>/dev/null | grep -q .
}

run_collect_with_retry() {
  local attempt=0
  local max_attempts=10
  local rc=0

  while true; do
    if "${collect_cmd[@]}"; then
      return 0
    fi

    rc=$?
    eprint "collect failed (exit=$rc)"
    if [[ -f "$lock_path" ]]; then
      eprint "collect.lock exists: $lock_path"
    fi

    # If there is nothing left in the queue, do not keep retrying.
    if ! queue_has_pending_checkins; then
      return "$rc"
    fi

    attempt=$((attempt+1))
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      eprint "Pending checkins still exist but collect keeps failing."
      eprint "Next action: run manually and inspect the error:"
      eprint "  ${collect_cmd[*]}"
      return "$rc"
    fi

    local sleep_s
    case "$attempt" in
      1) sleep_s="0.2" ;;
      2) sleep_s="0.5" ;;
      3) sleep_s="1" ;;
      4) sleep_s="2" ;;
      5) sleep_s="3" ;;
      *) sleep_s="5" ;;
    esac

    eprint "retrying in ${sleep_s}s (attempt ${attempt}/${max_attempts})"
    sleep "$sleep_s"
  done
}

# --run-collect: just run collect with retry/backoff, then exit.
if [[ "$RUN_COLLECT_ONLY" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'collect_cmd=%s\n' "${collect_cmd[*]}"
    exit 0
  fi
  python3 "$SCRIPT_DIR/shogun-ops.py" status >/dev/null
  mkdir -p "$checkins_dir"
  run_collect_with_retry
  exit $?
fi

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

watchexec_once_supported=0
if [[ "$WATCH_TOOL" == "watchexec" ]]; then
  if watchexec --help 2>&1 | grep -q -- "--once"; then
    watchexec_once_supported=1
  fi
  if [[ "$ONCE" -eq 1 && "$watchexec_once_supported" -ne 1 ]]; then
    eprint "--once was requested but watchexec does not support --once."
    eprint "Next actions:"
    eprint "  - Upgrade watchexec (recommended)"
    eprint "  - Or install fswatch (macOS): brew install fswatch"
    exit 1
  fi
fi

watch_cmd_str=""
case "$WATCH_TOOL" in
  fswatch)
    watch_cmd_str="fswatch -r '$checkins_dir'"
    ;;
  watchexec)
    watch_cmd_str="watchexec -w '$checkins_dir' -- '$SCRIPT_DIR/shogun-watcher.sh' --run-collect"
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
mkdir -p "$checkins_dir"

case "$WATCH_TOOL" in
  fswatch)
    while IFS= read -r _event; do
      rc=0
      if run_collect_with_retry; then
        rc=0
      else
        rc=$?
      fi
      if [[ "$ONCE" -eq 1 ]]; then
        exit "$rc"
      fi
    done < <(fswatch -r "$checkins_dir")
    ;;

  inotifywait)
    while IFS= read -r _event; do
      rc=0
      if run_collect_with_retry; then
        rc=0
      else
        rc=$?
      fi
      if [[ "$ONCE" -eq 1 ]]; then
        exit "$rc"
      fi
    done < <(inotifywait -m -e create -e moved_to -r "$checkins_dir" 2>/dev/null)
    ;;

  watchexec)
    once_flag=()
    if [[ "$ONCE" -eq 1 ]]; then
      # Already validated above: watchexec must support --once when requested.
      once_flag=(--once)
    fi
    exec watchexec "${once_flag[@]}" -w "$checkins_dir" -- "$SCRIPT_DIR/shogun-watcher.sh" --run-collect
    ;;

  *)
    eprint "Internal error: unknown WATCH_TOOL=$WATCH_TOOL"
    exit 1
    ;;
esac
