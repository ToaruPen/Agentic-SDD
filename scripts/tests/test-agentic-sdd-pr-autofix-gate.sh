#!/usr/bin/env bash
#
# Test: agentic-sdd-pr-autofix.sh — receive/guard gate logic (AC1–AC3)
#
# Exercises the event parsing and deny-by-default guard chain WITHOUT
# requiring a real git repository.  All external commands (git, gh) are
# stubbed so the test is self-contained and fast.
#
set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/templates/ci/github-actions/scripts/agentic-sdd-pr-autofix.sh"

if [[ ! -x "$src" ]]; then
	eprint "Missing script or not executable: $src"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t autofix-gate-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

mkdir -p "$tmpdir/bin"

# ── Stub: git ────────────────────────────────────────────────────────
# Returns success for every git sub-command the script may call before
# the autofix execution phase.  The gate tests never reach that phase.
cat >"$tmpdir/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# hash-object: return a dummy SHA for validate_path_only_cmd
if [[ "${1:-}" == "hash-object" ]]; then
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  exit 0
fi
# rev-parse: --show-toplevel or HEAD
if [[ "${1:-}" == "rev-parse" ]]; then
  if [[ "${2:-}" == "--show-toplevel" ]]; then
    printf '%s\n' "${GIT_STUB_TOPLEVEL:-.}"
    exit 0
  fi
  printf 'aabbccdd\n'
  exit 0
fi
# check-ref-format
if [[ "${1:-}" == "check-ref-format" ]]; then
  exit 0
fi
# fetch / checkout / add / diff / commit / push / show / status
exit 0
EOF
chmod +x "$tmpdir/bin/git"

# ── Stub: gh ─────────────────────────────────────────────────────────
# Handles `gh api` for label checking and `gh pr view` for head info.
cat >"$tmpdir/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
set -euo pipefail

optin_label="${GH_STUB_OPTIN_LABEL:-autofix-enabled}"
has_label="${GH_STUB_HAS_LABEL:-true}"

if [[ "${1:-}" == "api" ]]; then
  endpoint="${2:-}"
  shift 2
  # Label endpoint: repos/{owner}/{repo}/issues/{number}
  if [[ "$endpoint" == repos/*/issues/[0-9]* && "$endpoint" != */comments* ]]; then
    if [[ "$*" == *"--jq"* ]]; then
      if [[ "$has_label" == "true" ]]; then
        printf '%s\n' "$optin_label"
      fi
      exit 0
    fi
  fi
  # comments endpoint (paginate): return empty
  if [[ "$endpoint" == */comments* ]]; then
    exit 0
  fi
  exit 0
fi

# gh pr view
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  if [[ "$*" == *"headRepository"* ]]; then
    printf '%s\n' "${GITHUB_REPOSITORY:-o/r}"
    exit 0
  fi
  if [[ "$*" == *"headRefName"* ]]; then
    printf '%s\n' "feature/test"
    exit 0
  fi
  if [[ "$*" == *"baseRefName"* ]]; then
    printf '%s\n' "main"
    exit 0
  fi
  exit 0
fi
exit 0
GHEOF
chmod +x "$tmpdir/bin/gh"

# ── Event fixtures ───────────────────────────────────────────────────
cat >"$tmpdir/ev-issue-pr-bot.json" <<'EOF'
{
  "issue": {
    "number": 42,
    "html_url": "https://github.com/o/r/pull/42",
    "pull_request": {"url": "https://api.github.com/repos/o/r/pulls/42"}
  },
  "comment": {
    "id": 500,
    "html_url": "https://github.com/o/r/pull/42#issuecomment-500",
    "body": "please fix",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

cat >"$tmpdir/ev-issue-nonpr.json" <<'EOF'
{
  "issue": {
    "number": 999,
    "html_url": "https://github.com/o/r/issues/999"
  },
  "comment": {
    "id": 600,
    "html_url": "https://github.com/o/r/issues/999#issuecomment-600",
    "body": "status update",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

cat >"$tmpdir/ev-review-bot.json" <<'EOF'
{
  "pull_request": {
    "number": 43,
    "html_url": "https://github.com/o/r/pull/43"
  },
  "review": {
    "id": 700,
    "html_url": "https://github.com/o/r/pull/43#pullrequestreview-700",
    "body": "nit: rename",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

cat >"$tmpdir/ev-inline-bot.json" <<'EOF'
{
  "pull_request": {
    "number": 44,
    "html_url": "https://github.com/o/r/pull/44"
  },
  "comment": {
    "id": 800,
    "html_url": "https://github.com/o/r/pull/44#discussion_r800",
    "body": "please fix inline",
    "user": {"login": "chatgpt-codex-connector[bot]"}
  }
}
EOF

cat >"$tmpdir/ev-nonbot.json" <<'EOF'
{
  "pull_request": {
    "number": 45,
    "html_url": "https://github.com/o/r/pull/45"
  },
  "comment": {
    "id": 900,
    "html_url": "https://github.com/o/r/pull/45#discussion_r900",
    "body": "human comment",
    "user": {"login": "octocat"}
  }
}
EOF

# ── Shared env ───────────────────────────────────────────────────────
# Create a dummy autofix command so validate_path_only_cmd passes
dummy_work="$tmpdir/work"
mkdir -p "$dummy_work/scripts"
cat >"$dummy_work/scripts/mock-autofix.sh" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$dummy_work/scripts/mock-autofix.sh"

export PATH="$tmpdir/bin:$PATH"
export GH_TOKEN=dummy
export GITHUB_REPOSITORY=o/r
export GITHUB_RUN_ID=99999
export AGENTIC_SDD_AUTOFIX_CMD=./scripts/mock-autofix.sh
export AGENTIC_SDD_AUTOFIX_BOT_LOGINS='coderabbitai[bot],chatgpt-codex-connector[bot]'
export AGENTIC_SDD_PR_REVIEW_MENTION='@pr-bots review'
export AGENTIC_SDD_AUTOFIX_OPTIN_LABEL='autofix-enabled'
export AGENTIC_SDD_AUTOFIX_MAX_ITERS=10
export GIT_STUB_TOPLEVEL="$dummy_work"
export GH_STUB_HAS_LABEL=true

run_script() {
	local event_path="$1"
	(cd "$dummy_work" && GITHUB_EVENT_PATH="$event_path" bash "$src") 2>&1
}

# ═════════════════════════════════════════════════════════════════════
# Test 1 (AC1): issue_comment on PR with bot → extracts type + pr_number
# ═════════════════════════════════════════════════════════════════════
out1="$(run_script "$tmpdir/ev-issue-pr-bot.json")"
if ! printf '%s' "$out1" | grep -Fq 'type=issue_comment pr_number=42'; then
	eprint "Test 1 FAIL: expected type=issue_comment pr_number=42 in output"
	eprint "Got: $out1"
	exit 1
fi
if ! printf '%s' "$out1" | grep -Fq 'decision=proceed'; then
	eprint "Test 1 FAIL: expected decision=proceed in output"
	eprint "Got: $out1"
	exit 1
fi
eprint "Test 1 PASS: issue_comment PR bot → proceed with type + pr_number"

# ═════════════════════════════════════════════════════════════════════
# Test 2 (AC1): pull_request_review → type=review
# ═════════════════════════════════════════════════════════════════════
out2="$(run_script "$tmpdir/ev-review-bot.json")"
if ! printf '%s' "$out2" | grep -Fq 'type=review pr_number=43'; then
	eprint "Test 2 FAIL: expected type=review pr_number=43"
	eprint "Got: $out2"
	exit 1
fi
eprint "Test 2 PASS: pull_request_review → type=review"

# ═════════════════════════════════════════════════════════════════════
# Test 2b (AC1): pull_request_review_comment → type=inline
# ═════════════════════════════════════════════════════════════════════
out2b="$(run_script "$tmpdir/ev-inline-bot.json")"
if ! printf '%s' "$out2b" | grep -Fq 'type=inline pr_number=44'; then
	eprint "Test 2b FAIL: expected type=inline pr_number=44"
	eprint "Got: $out2b"
	exit 1
fi
eprint "Test 2b PASS: pull_request_review_comment → type=inline"

# ═════════════════════════════════════════════════════════════════════
# Test 3 (AC2): Non-PR issue_comment → no-op early exit
# ═════════════════════════════════════════════════════════════════════
out3="$(run_script "$tmpdir/ev-issue-nonpr.json")"
if ! printf '%s' "$out3" | grep -Fq 'Not a PR event'; then
	eprint "Test 3 FAIL: expected 'Not a PR event' no-op"
	eprint "Got: $out3"
	exit 1
fi
eprint "Test 3 PASS: non-PR issue_comment → no-op"

# ═════════════════════════════════════════════════════════════════════
# Test 4 (AC2): Bot allowlist miss → no-op
# ═════════════════════════════════════════════════════════════════════
out4="$(run_script "$tmpdir/ev-nonbot.json")"
if ! printf '%s' "$out4" | grep -Fq 'not allowlisted'; then
	eprint "Test 4 FAIL: expected non-allowlisted no-op"
	eprint "Got: $out4"
	exit 1
fi
eprint "Test 4 PASS: non-bot actor → no-op"

# ═════════════════════════════════════════════════════════════════════
# Test 5 (AC2): Missing required env var → fail-fast
# ═════════════════════════════════════════════════════════════════════
set +e
out5="$(cd "$dummy_work" && GITHUB_EVENT_PATH="$tmpdir/ev-issue-pr-bot.json" \
	AGENTIC_SDD_AUTOFIX_BOT_LOGINS='' \
	bash "$src" 2>&1)"
rc5=$?
set -e
if [[ "$rc5" -eq 0 ]]; then
	eprint "Test 5 FAIL: expected non-zero exit for missing AGENTIC_SDD_AUTOFIX_BOT_LOGINS"
	exit 1
fi
if ! printf '%s' "$out5" | grep -Fq 'Missing AGENTIC_SDD_AUTOFIX_BOT_LOGINS'; then
	eprint "Test 5 FAIL: expected missing allowlist error"
	eprint "Got: $out5"
	exit 1
fi

set +e
out5b="$(cd "$dummy_work" && GITHUB_EVENT_PATH="$tmpdir/ev-issue-pr-bot.json" \
	AGENTIC_SDD_PR_REVIEW_MENTION='' \
	bash "$src" 2>&1)"
rc5b=$?
set -e
if [[ "$rc5b" -eq 0 ]]; then
	eprint "Test 5b FAIL: expected non-zero exit for missing AGENTIC_SDD_PR_REVIEW_MENTION"
	exit 1
fi
if ! printf '%s' "$out5b" | grep -Fq 'Missing AGENTIC_SDD_PR_REVIEW_MENTION'; then
	eprint "Test 5b FAIL: expected missing mention error"
	eprint "Got: $out5b"
	exit 1
fi

set +e
out5c="$(cd "$dummy_work" && GITHUB_EVENT_PATH='' \
	bash "$src" 2>&1)"
rc5c=$?
set -e
if [[ "$rc5c" -eq 0 ]]; then
	eprint "Test 5c FAIL: expected non-zero exit for missing GITHUB_EVENT_PATH"
	exit 1
fi
if ! printf '%s' "$out5c" | grep -Fq 'Missing GITHUB_EVENT_PATH'; then
	eprint "Test 5c FAIL: expected missing event path error"
	eprint "Got: $out5c"
	exit 1
fi
eprint "Test 5 PASS: missing required env vars → fail-fast"

# ═════════════════════════════════════════════════════════════════════
# Test 6 (AC3): Both proceed and no-op paths produce log output
# ═════════════════════════════════════════════════════════════════════
# proceed path: already checked in Test 1 (decision=proceed)
# no-op path: already checked in Test 3 (Not a PR event) and Test 4 (not allowlisted)
# Extra: verify the [AUTOFIX] prefix is present on both paths
if ! printf '%s' "$out1" | grep -Fq '[AUTOFIX]'; then
	eprint "Test 6 FAIL: expected [AUTOFIX] prefix in proceed output"
	exit 1
fi
if ! printf '%s' "$out3" | grep -Fq '[AUTOFIX]'; then
	eprint "Test 6 FAIL: expected [AUTOFIX] prefix in no-op output"
	exit 1
fi
eprint "Test 6 PASS: log output present on both proceed and no-op paths"

# ═════════════════════════════════════════════════════════════════════
# Test 7 (AC2): Opt-in label missing → no-op
# ═════════════════════════════════════════════════════════════════════
out7="$(GH_STUB_HAS_LABEL=false run_script "$tmpdir/ev-issue-pr-bot.json")"
if ! printf '%s' "$out7" | grep -Fq 'Opt-in label not present'; then
	eprint "Test 7 FAIL: expected opt-in label no-op"
	eprint "Got: $out7"
	exit 1
fi
eprint "Test 7 PASS: missing opt-in label → no-op"

# ═════════════════════════════════════════════════════════════════════
eprint ""
eprint "OK: scripts/tests/test-agentic-sdd-pr-autofix-gate.sh (7/7 passed)"
