#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/ui-iterate.sh <issue-number> [round-id] [options]

Capture UI screenshots for iterative redesign and optionally run checks.

Positional arguments:
  issue-number                Issue number (e.g. 99 or issue-99)
  round-id                    Optional round id (e.g. round-01 or 1)

Options:
  --route <path>              Target route (default: /)
  --base-url <url>            Base URL (default: $WF_BASE_URL or http://127.0.0.1:5173)
  --out-root <dir>            Output root (default: var/screenshot)
  --desktop-size <WxH>        Desktop viewport (default: 1280x720)
  --mobile-size <WxH>         Mobile viewport (default: 390x844)
  --check-cmd <command>       Check command to run (repeatable)
  --skip-checks               Skip checks
  --capture-cmd <command>     Custom capture command (uses env vars below)
  --skip-capture              Skip screenshot capture
  --note <text>               Save note in round metadata
  --dry-run                   Print plan only
  -h, --help                  Show help

Env vars:
  UI_ITERATE_CHECK_CMDS       Newline-separated default check commands
  UI_ITERATE_CAPTURE_CMD      Default capture command when --capture-cmd is omitted

Capture command env:
  UI_ITERATE_URL              Target URL
  UI_ITERATE_DESKTOP_FILE     Desktop screenshot path
  UI_ITERATE_MOBILE_FILE      Mobile screenshot path
  UI_ITERATE_DESKTOP_SIZE     Desktop size (WxH)
  UI_ITERATE_MOBILE_SIZE      Mobile size (WxH)
  UI_ITERATE_DESKTOP_WIDTH    Desktop width
  UI_ITERATE_DESKTOP_HEIGHT   Desktop height
  UI_ITERATE_MOBILE_WIDTH     Mobile width
  UI_ITERATE_MOBILE_HEIGHT    Mobile height

Examples:
  ./scripts/ui-iterate.sh 99 --route /kiosk \
    --check-cmd "npm run -w web typecheck" \
    --check-cmd "npm run -w web lint" \
    --check-cmd "npm run -w web test"

  ./scripts/ui-iterate.sh 99 round-02 --route /staff --skip-checks

Outputs:
  <out-root>/issue-<n>/round-<xx>/
    - <route>-desktop.png
    - <route>-mobile.png
    - checks/*.log
    - checks/commands.txt
    - meta.txt

EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    eprint "Missing command: $cmd"
    exit 1
  fi
}

normalize_issue_number() {
  local raw="$1"
  if [[ "$raw" =~ ^issue-([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$raw"
    return 0
  fi
  return 1
}

normalize_round_id() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    return 1
  fi
  if [[ "$raw" =~ ^round-([0-9]+)$ ]]; then
    printf 'round-%02d\n' "$((10#${BASH_REMATCH[1]}))"
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf 'round-%02d\n' "$((10#$raw))"
    return 0
  fi
  return 1
}

validate_size() {
  local raw="$1"
  if [[ ! "$raw" =~ ^[0-9]+x[0-9]+$ ]]; then
    return 1
  fi
  local w="${raw%x*}"
  local h="${raw#*x}"
  if [[ "$w" -lt 200 || "$h" -lt 200 ]]; then
    return 1
  fi
  return 0
}

next_round_id() {
  local issue_dir="$1"
  local max_n=0
  if [[ -d "$issue_dir" ]]; then
    while IFS= read -r path; do
      local base
      base="$(basename "$path")"
      if [[ "$base" =~ ^round-([0-9]+)$ ]]; then
        local n=$((10#${BASH_REMATCH[1]}))
        if [[ "$n" -gt "$max_n" ]]; then
          max_n="$n"
        fi
      fi
    done < <(find "$issue_dir" -maxdepth 1 -type d -name 'round-*' 2>/dev/null || true)
  fi
  printf 'round-%02d\n' "$((max_n + 1))"
}

run_check() {
  local cmd="$1"
  local log_file="$2"

  set +e
  bash -lc "$cmd" >"$log_file" 2>&1
  local ec=$?
  set -e
  return "$ec"
}

run_builtin_capture() {
  local url="$1"
  local desktop_file="$2"
  local mobile_file="$3"
  local desktop_w="$4"
  local desktop_h="$5"
  local mobile_w="$6"
  local mobile_h="$7"

  require_cmd node
  require_cmd curl

  if ! curl -fsS "$url" >/dev/null; then
    eprint "Target URL is unreachable: $url"
    eprint "Start your app server first, or use --capture-cmd / --skip-capture"
    return 1
  fi

  node - "$url" "$desktop_file" "$mobile_file" "$desktop_w" "$desktop_h" "$mobile_w" "$mobile_h" <<'NODE'
const [url, desktopFile, mobileFile, desktopW, desktopH, mobileW, mobileH] = process.argv.slice(2);

const { chromium } = require("playwright");

const toInt = (value, name) => {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`invalid ${name}: ${value}`);
  }
  return parsed;
};

const capture = async (page, path) => {
  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
  if (!response || !response.ok()) {
    const status = response ? response.status() : "no-response";
    throw new Error(`failed to load ${url} (${status})`);
  }
  await page.waitForLoadState("networkidle", { timeout: 10_000 }).catch(() => {
    // Best-effort only.
  });
  await page.waitForTimeout(1200);
  await page.screenshot({ path, fullPage: true });
};

const main = async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const desktopPage = await browser.newPage({
      viewport: { width: toInt(desktopW, "desktopW"), height: toInt(desktopH, "desktopH") },
    });
    await capture(desktopPage, desktopFile);
    await desktopPage.close();

    const mobilePage = await browser.newPage({
      viewport: { width: toInt(mobileW, "mobileW"), height: toInt(mobileH, "mobileH") },
      isMobile: true,
      hasTouch: true,
      deviceScaleFactor: 2,
    });
    await capture(mobilePage, mobileFile);
    await mobilePage.close();
  } finally {
    await browser.close();
  }
};

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
NODE
}

issue_arg=""
round_arg=""

route="/"
base_url="${WF_BASE_URL:-http://127.0.0.1:5173}"
out_root="var/screenshot"
desktop_size="1280x720"
mobile_size="390x844"
run_checks=1
run_capture=1
dry_run=0
note=""
capture_cmd="${UI_ITERATE_CAPTURE_CMD:-}"

declare -a check_cmds=()
if [[ -n "${UI_ITERATE_CHECK_CMDS:-}" ]]; then
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      check_cmds+=("$line")
    fi
  done <<< "${UI_ITERATE_CHECK_CMDS}"
fi

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --route)
      route="${2:-}"
      shift 2
      ;;
    --base-url)
      base_url="${2:-}"
      shift 2
      ;;
    --out-root)
      out_root="${2:-}"
      shift 2
      ;;
    --desktop-size)
      desktop_size="${2:-}"
      shift 2
      ;;
    --mobile-size)
      mobile_size="${2:-}"
      shift 2
      ;;
    --check-cmd)
      check_cmds+=("${2:-}")
      shift 2
      ;;
    --skip-checks)
      run_checks=0
      shift
      ;;
    --capture-cmd)
      capture_cmd="${2:-}"
      shift 2
      ;;
    --skip-capture)
      run_capture=0
      shift
      ;;
    --note)
      note="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        args+=("$1")
        shift
      done
      ;;
    -*)
      eprint "Unknown option: $1"
      usage
      exit 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "${#args[@]}" -lt 1 || "${#args[@]}" -gt 2 ]]; then
  usage
  exit 2
fi

issue_arg="${args[0]}"
round_arg="${args[1]:-}"

issue_number="$(normalize_issue_number "$issue_arg" || true)"
if [[ -z "$issue_number" ]]; then
  eprint "Invalid issue-number: $issue_arg"
  exit 2
fi

if [[ -n "$round_arg" ]]; then
  round_id="$(normalize_round_id "$round_arg" || true)"
  if [[ -z "$round_id" ]]; then
    eprint "Invalid round-id: $round_arg (use round-01 or 1)"
    exit 2
  fi
else
  round_id=""
fi

if [[ -z "$route" ]]; then
  eprint "--route is required"
  exit 2
fi
if [[ "$route" != /* ]]; then
  route="/$route"
fi

if ! validate_size "$desktop_size"; then
  eprint "Invalid --desktop-size: $desktop_size (expected WxH, minimum 200x200)"
  exit 2
fi
if ! validate_size "$mobile_size"; then
  eprint "Invalid --mobile-size: $mobile_size (expected WxH, minimum 200x200)"
  exit 2
fi

require_cmd git

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  eprint "Not in a git repository"
  exit 1
fi

issue_dir="$repo_root/$out_root/issue-$issue_number"
if [[ -z "$round_id" ]]; then
  round_id="$(next_round_id "$issue_dir")"
fi
round_dir="$issue_dir/$round_id"
checks_dir="$round_dir/checks"

route_slug="$(printf '%s' "$route" | sed -E 's#^/##; s#[^A-Za-z0-9]+#-#g; s#(^-|-$)##g')"
if [[ -z "$route_slug" ]]; then
  route_slug="home"
fi

target_url="${base_url%/}${route}"

desktop_w="${desktop_size%x*}"
desktop_h="${desktop_size#*x}"
mobile_w="${mobile_size%x*}"
mobile_h="${mobile_size#*x}"

desktop_file="$round_dir/${route_slug}-desktop.png"
mobile_file="$round_dir/${route_slug}-mobile.png"

if [[ "$dry_run" -eq 1 ]]; then
  eprint "Plan:"
  eprint "- repo_root: $repo_root"
  eprint "- issue: $issue_number"
  eprint "- round: $round_id"
  eprint "- route: $route"
  eprint "- target_url: $target_url"
  eprint "- out_dir: $round_dir"
  eprint "- desktop_size: $desktop_size"
  eprint "- mobile_size: $mobile_size"
  eprint "- run_checks: $run_checks"
  if [[ "$run_checks" -eq 1 ]]; then
    eprint "- check_cmd_count: ${#check_cmds[@]}"
  fi
  eprint "- run_capture: $run_capture"
  if [[ "$run_capture" -eq 1 ]]; then
    if [[ -n "$capture_cmd" ]]; then
      eprint "- capture_mode: custom-command"
    else
      eprint "- capture_mode: builtin-playwright"
    fi
  fi
  exit 0
fi

mkdir -p "$checks_dir"

meta_file="$round_dir/meta.txt"
{
  printf 'issue=%s\n' "$issue_number"
  printf 'round=%s\n' "$round_id"
  printf 'route=%s\n' "$route"
  printf 'target_url=%s\n' "$target_url"
  printf 'desktop_size=%s\n' "$desktop_size"
  printf 'mobile_size=%s\n' "$mobile_size"
  printf 'timestamp=%s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
  if [[ -n "$note" ]]; then
    printf 'note=%s\n' "$note"
  fi
} > "$meta_file"

if [[ "$run_checks" -eq 1 ]]; then
  if [[ "${#check_cmds[@]}" -eq 0 ]]; then
    eprint "No check commands configured. Use --check-cmd (repeatable) or --skip-checks."
    exit 2
  fi

  check_manifest="$checks_dir/commands.txt"
  : > "$check_manifest"

  idx=0
  for cmd in "${check_cmds[@]}"; do
    if [[ -z "$cmd" ]]; then
      continue
    fi
    idx=$((idx + 1))
    log_file="$checks_dir/check-$(printf '%02d' "$idx").log"

    if run_check "$cmd" "$log_file"; then
      printf 'ok\t%s\t%s\n' "$cmd" "${log_file#$repo_root/}" >> "$check_manifest"
    else
      printf 'fail\t%s\t%s\n' "$cmd" "${log_file#$repo_root/}" >> "$check_manifest"
      eprint "Check failed (see log): ${log_file#$repo_root/}"
      exit 1
    fi
  done
fi

if [[ "$run_capture" -eq 1 ]]; then
  if [[ -n "$capture_cmd" ]]; then
    export UI_ITERATE_URL="$target_url"
    export UI_ITERATE_DESKTOP_FILE="$desktop_file"
    export UI_ITERATE_MOBILE_FILE="$mobile_file"
    export UI_ITERATE_DESKTOP_SIZE="$desktop_size"
    export UI_ITERATE_MOBILE_SIZE="$mobile_size"
    export UI_ITERATE_DESKTOP_WIDTH="$desktop_w"
    export UI_ITERATE_DESKTOP_HEIGHT="$desktop_h"
    export UI_ITERATE_MOBILE_WIDTH="$mobile_w"
    export UI_ITERATE_MOBILE_HEIGHT="$mobile_h"

    set +e
    bash -lc "$capture_cmd"
    ec=$?
    set -e
    if [[ "$ec" -ne 0 ]]; then
      eprint "Capture command failed (exit=$ec)"
      exit "$ec"
    fi
  else
    if ! run_builtin_capture "$target_url" "$desktop_file" "$mobile_file" "$desktop_w" "$desktop_h" "$mobile_w" "$mobile_h"; then
      eprint "Builtin capture failed. Install Playwright in your project or use --capture-cmd."
      exit 1
    fi
  fi
fi

printf '%s\n' "UI iteration round generated:"
printf '%s\n' "- meta: ${meta_file#$repo_root/}"
if [[ "$run_capture" -eq 1 ]]; then
  printf '%s\n' "- screenshot(desktop): ${desktop_file#$repo_root/}"
  printf '%s\n' "- screenshot(mobile): ${mobile_file#$repo_root/}"
fi
if [[ "$run_checks" -eq 1 ]]; then
  printf '%s\n' "- checks: ${checks_dir#$repo_root/}"
fi
