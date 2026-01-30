#!/usr/bin/env bash

set -euo pipefail

# Shogun Ops tmux launcher
# - Deterministic session + pane layout
# - Deterministic send-keys for order injection
#
# Implementation note:
# - Avoid relying on pane index (pane-base-index / base-index may be customized).
# - Prefer tmux pane_id (%...) and pane_title lookups.

SESSION_DEFAULT="shogun-ops"
WINDOW_DEFAULT="ops"

usage() {
  cat <<'EOF'
Usage: scripts/shogun-tmux.sh [--dry-run] [--session <name>] [--window <name>] <command> [args]

Commands:
  init        Create a deterministic tmux session + pane layout (idempotent)
  send-order  Send the default order injection command to the 'middle' pane
  attach      Attach to the session

Options:
  --dry-run           Print tmux commands instead of executing them
  --session <name>    tmux session name (default: shogun-ops)
  --window <name>     tmux window name  (default: ops)

send-order options:
  --cmd <string>      Command string to send (default: "python3 scripts/shogun-ops.py supervise --once")

Examples:
  # Show the tmux command sequence
  ./scripts/shogun-tmux.sh --dry-run init

  # Create the session (requires tmux)
  ./scripts/shogun-tmux.sh init

  # Send order injection command to the middle pane
  ./scripts/shogun-tmux.sh send-order

  # Attach
  ./scripts/shogun-tmux.sh attach
EOF
}

eprint() { printf '%s\n' "$*" >&2; }

shell_quote() {
  # Quote one argument for human-readable dry-run output.
  local s="$1"
  if [[ "$s" =~ [^A-Za-z0-9_./:-] ]]; then
    s="'${s//"'"/"'\\''"}'"
  fi
  printf '%s' "$s"
}

print_cmd() {
  local out=""
  for a in "$@"; do
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$(shell_quote "$a")"
  done
  printf '%s\n' "$out"
}

require_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    return 0
  fi

  eprint "tmux not found."
  eprint "Next action: install tmux."
  eprint "  - macOS (Homebrew): brew install tmux"
  eprint "  - Debian/Ubuntu:    sudo apt-get install tmux"
  return 127
}

has_session() {
  local session="$1"
  tmux has-session -t "$session" >/dev/null 2>&1
}

run_tmux() {
  local dry_run="$1"; shift
  if [[ "$dry_run" -eq 1 ]]; then
    print_cmd tmux "$@"
    return 0
  fi
  tmux "$@"
}

tmux_capture() {
  # Execute a tmux command that prints a value (e.g. -P -F '#{pane_id}').
  # NOTE: Do not print anything to stdout in dry-run mode because callers may use
  # command substitution (e.g. pane_id="$(tmux_capture ...)"), which would corrupt
  # the dry-run command sequence.
  local dry_run="$1"
  local placeholder="$2"
  shift 2

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%s' "$placeholder"
    return 0
  fi

  tmux "$@"
}

find_pane_id_by_title() {
  local dry_run="$1"
  local session="$2"
  local window="$3"
  local title="$4"

  if [[ "$dry_run" -eq 1 ]]; then
    # In dry-run, return only the placeholder (see tmux_capture note).
    case "$title" in
      upper) printf '%s' "%upper" ;;
      middle) printf '%s' "%middle" ;;
      ashigaru1) printf '%s' "%ashigaru1" ;;
      ashigaru2) printf '%s' "%ashigaru2" ;;
      ashigaru3) printf '%s' "%ashigaru3" ;;
      *) printf '%s' "%pane" ;;
    esac
    return 0
  fi

  local line
  while IFS=$'\t' read -r pane_id pane_title; do
    if [[ "$pane_title" == "$title" ]]; then
      printf '%s' "$pane_id"
      return 0
    fi
  done < <(tmux list-panes -t "$session:$window" -F "#{pane_id}\t#{pane_title}")

  return 1
}

cmd_init() {
  local dry_run="$1"
  local session="$2"
  local window="$3"

  if [[ "$dry_run" -ne 1 ]]; then
    require_tmux
    if has_session "$session"; then
      eprint "tmux session already exists: $session"
      return 0
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    # In dry-run mode, print executable tmux commands to stdout.
    # Do NOT use command substitution (pane_id="$(...)"), because mixing command
    # logging and captured values would corrupt the printed command sequence.
    local upper_id="%upper"
    local middle_id="%middle"
    local ash1_id="%ashigaru1"
    local ash2_id="%ashigaru2"
    local ash3_id="%ashigaru3"

    print_cmd tmux new-session -d -s "$session" -n "$window" -P -F "#{pane_id}"
    print_cmd tmux select-pane -t "$upper_id" -T upper

    print_cmd tmux split-window -h -t "$upper_id" -P -F "#{pane_id}"
    print_cmd tmux select-pane -t "$middle_id" -T middle

    print_cmd tmux split-window -v -t "$middle_id" -P -F "#{pane_id}"
    print_cmd tmux select-pane -t "$ash1_id" -T ashigaru1

    print_cmd tmux split-window -v -t "$ash1_id" -P -F "#{pane_id}"
    print_cmd tmux select-pane -t "$ash2_id" -T ashigaru2

    print_cmd tmux split-window -v -t "$ash2_id" -P -F "#{pane_id}"
    print_cmd tmux select-pane -t "$ash3_id" -T ashigaru3

    print_cmd tmux select-pane -t "$middle_id"
    return 0
  fi

  # Create session and capture the initial pane id.
  local upper_id
  upper_id="$(tmux_capture "$dry_run" "%upper" new-session -d -s "$session" -n "$window" -P -F "#{pane_id}")"
  run_tmux "$dry_run" select-pane -t "$upper_id" -T upper

  # Split to create the right column (middle).
  local middle_id
  middle_id="$(tmux_capture "$dry_run" "%middle" split-window -h -t "$upper_id" -P -F "#{pane_id}")"
  run_tmux "$dry_run" select-pane -t "$middle_id" -T middle

  # Stack ashigaru panes under the right column (split the most recent bottom pane).
  local ash1_id
  ash1_id="$(tmux_capture "$dry_run" "%ashigaru1" split-window -v -t "$middle_id" -P -F "#{pane_id}")"
  run_tmux "$dry_run" select-pane -t "$ash1_id" -T ashigaru1

  local ash2_id
  ash2_id="$(tmux_capture "$dry_run" "%ashigaru2" split-window -v -t "$ash1_id" -P -F "#{pane_id}")"
  run_tmux "$dry_run" select-pane -t "$ash2_id" -T ashigaru2

  local ash3_id
  ash3_id="$(tmux_capture "$dry_run" "%ashigaru3" split-window -v -t "$ash2_id" -P -F "#{pane_id}")"
  run_tmux "$dry_run" select-pane -t "$ash3_id" -T ashigaru3

  # Focus middle by default.
  run_tmux "$dry_run" select-pane -t "$middle_id"
}

cmd_send_order() {
  local dry_run="$1"
  local session="$2"
  local window="$3"
  local cmd_str="$4"

  if [[ "$dry_run" -ne 1 ]]; then
    require_tmux
    if ! has_session "$session"; then
      eprint "tmux session not found: $session"
      eprint "Next action: run: ./scripts/shogun-tmux.sh init"
      return 2
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    # Print commands deterministically; use a placeholder pane id for 'middle'.
    print_cmd tmux list-panes -t "$session:$window" -F "#{pane_id}\t#{pane_title}"
    local target_pane="%middle"
    print_cmd tmux send-keys -t "$target_pane" "$cmd_str" Enter
    return 0
  fi

  local target_pane
  if ! target_pane="$(find_pane_id_by_title "$dry_run" "$session" "$window" middle)"; then
    eprint "tmux pane titled 'middle' not found in: $session:$window"
    eprint "Next action: run: ./scripts/shogun-tmux.sh init (or fix pane titles)"
    return 2
  fi

  run_tmux "$dry_run" send-keys -t "$target_pane" "$cmd_str" Enter
}

cmd_attach() {
  local dry_run="$1"
  local session="$2"

  if [[ "$dry_run" -ne 1 ]]; then
    require_tmux
    if ! has_session "$session"; then
      eprint "tmux session not found: $session"
      eprint "Next action: run: ./scripts/shogun-tmux.sh init"
      return 2
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    print_cmd tmux attach -t "$session"
    return 0
  fi

  tmux attach -t "$session"
}

main() {
  local dry_run=0
  local session="$SESSION_DEFAULT"
  local window="$WINDOW_DEFAULT"

  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1; shift ;;
      --session)
        session="$2"; shift 2 ;;
      --window)
        window="$2"; shift 2 ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  local cmd="$1"; shift
  case "$cmd" in
    init)
      cmd_init "$dry_run" "$session" "$window"
      ;;
    send-order)
      local cmd_str="python3 scripts/shogun-ops.py supervise --once"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --cmd)
            cmd_str="$2"; shift 2 ;;
          -h|--help)
            usage
            exit 0
            ;;
          *)
            eprint "Unknown arg for send-order: $1"
            exit 2
            ;;
        esac
      done
      cmd_send_order "$dry_run" "$session" "$window" "$cmd_str"
      ;;
    attach)
      cmd_attach "$dry_run" "$session"
      ;;
    *)
      eprint "Unknown command: $cmd"
      usage
      exit 2
      ;;
  esac
}

main "$@"
