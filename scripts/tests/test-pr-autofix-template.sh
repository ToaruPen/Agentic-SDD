#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/templates/ci/github-actions/scripts/agentic-sdd-pr-autofix.sh"

if [[ ! -x "$src" ]]; then
  eprint "Missing script or not executable: $src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t autofix-template-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

work="$tmpdir/work"
remote="$tmpdir/remote.git"
mkdir -p "$work" "$tmpdir/bin"

git -C "$work" init -q
git -C "$work" config user.name tester
git -C "$work" config user.email tester@example.com
printf '%s\n' "hello" > "$work/sample.txt"
git -C "$work" add sample.txt
git -C "$work" commit -m init -q

git init -q --bare "$remote"
git -C "$work" remote add origin "$remote"
git -C "$work" checkout -b feature/test-autofix -q
git -C "$work" push -u origin feature/test-autofix -q

mkdir -p "$work/scripts"
cp -p "$src" "$work/scripts/agentic-sdd-pr-autofix.sh"

cat > "$work/scripts/mock-autofix.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$AGENTIC_SDD_AUTOFIX_EVENT_TYPE" > .event_type
printf '%s\n' "$AGENTIC_SDD_AUTOFIX_PR_NUMBER" > .pr_number
printf '%s\n' "$AGENTIC_SDD_AUTOFIX_COMMENT_USER" > .comment_user
printf '%s\n' "fix" >> sample.txt
EOF
chmod +x "$work/scripts/mock-autofix.sh" "$work/scripts/agentic-sdd-pr-autofix.sh"

cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${GH_STUB_LOG:?}"
comments_file="${GH_STUB_COMMENTS:?}"
repo="${GITHUB_REPOSITORY:?}"
head_repo="${GH_STUB_HEAD_REPO:?}"
head_ref="${GH_STUB_HEAD_REF:?}"
base_ref="${GH_STUB_BASE_REF:-main}"
optin_label="${GH_STUB_OPTIN_LABEL:-autofix-enabled}"
marker_text='<!-- agentic-sdd:autofix v1 -->'
status_applied='Autofix applied and pushed.'
status_push_failed='Autofix produced changes but could not push'
status_max_iters='Autofix stopped: reached max iterations'

printf '%s\n' "$*" >> "$log_file"

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  if [[ "$*" == *"--json headRepository"* ]]; then
    printf '%s\n' "$head_repo"
    exit 0
  fi
  if [[ "$*" == *"--json headRefName"* ]]; then
    printf '%s\n' "$head_ref"
    exit 0
  fi
  if [[ "$*" == *"--json baseRefName"* ]]; then
    printf '%s\n' "$base_ref"
    exit 0
  fi
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  endpoint="${2:-}"
  shift 2
  if [[ "$endpoint" == "repos/$repo/issues/104" ]]; then
    printf '%s\n' "$optin_label"
    exit 0
  fi
  if [[ "$endpoint" == "repos/$repo/issues/104/comments" ]]; then
    if [[ "$*" == *"--paginate"* ]]; then
      if [[ "$*" == *"Autofix stopped: reached max iterations"* ]]; then
        if [[ -f "$comments_file" ]]; then
          awk -v marker_text="$marker_text" -v status_applied="$status_applied" -v status_push_failed="$status_push_failed" -v status_max_iters="$status_max_iters" '
            BEGIN { in_body=0; body=""; id=0 }
            /^<<<COMMENT>>>$/ { in_body=1; body=""; next }
            /^<<<END>>>$/ {
              if (index(body, marker_text) > 0 && \
                  (index(body, status_applied) > 0 ||
                   index(body, status_push_failed) > 0 ||
                   index(body, status_max_iters) > 0)) {
                id += 1
                print id
              }
              in_body=0
              body=""
              next
            }
            {
              if (in_body) {
                if (body == "") body=$0; else body=body "\n" $0
              }
            }
          ' "$comments_file"
        fi
      elif [[ "$*" == *"Autofix applied and pushed."* && "$*" == *"Source event:"* ]]; then
        source_key=""
        if [[ "$*" =~ Source\ event:\ ([^\"]+) ]]; then
          source_key="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$source_key" && -f "$comments_file" ]]; then
          awk -v source_key="$source_key" -v status_applied="$status_applied" '
            BEGIN { in_body=0; body="" }
            /^<<<COMMENT>>>$/ { in_body=1; body=""; next }
            /^<<<END>>>$/ {
              if (index(body, status_applied) > 0 && index(body, "Source event: " source_key) > 0) {
                print "1"
              }
              in_body=0
              body=""
              next
            }
            {
              if (in_body) {
                if (body == "") body=$0; else body=body "\n" $0
              }
            }
          ' "$comments_file"
        fi
      elif [[ -f "$comments_file" ]]; then
        awk '
          BEGIN { in_body=0 }
          /^<<<COMMENT>>>$/ { in_body=1; next }
          /^<<<END>>>$/ { in_body=0; next }
          { if (in_body) print }
        ' "$comments_file"
      fi
      exit 0
    fi
    body=""
    for arg in "$@"; do
      case "$arg" in
        body=*) body="${arg#body=}" ;;
      esac
    done
    printf '%s\n%s\n%s\n' '<<<COMMENT>>>' "$body" '<<<END>>>' >> "$comments_file"
    exit 0
  fi
fi

exit 0
EOF
chmod +x "$tmpdir/bin/gh"

event_issue="$tmpdir/event-issue.json"
cat > "$event_issue" <<'EOF'
{
  "issue": {
    "number": 104,
    "pull_request": {"url": "https://api.github.com/repos/o/r/pulls/104"}
  },
  "comment": {
    "id": 101,
    "html_url": "https://github.com/o/r/pull/104#issuecomment-101",
    "body": "please fix",
    "user": {"login": "chatgpt-codex-connector[bot]"}
  }
}
EOF

event_inline_nonbot="$tmpdir/event-inline-nonbot.json"
cat > "$event_inline_nonbot" <<'EOF'
{
  "pull_request": {
    "number": 104,
    "html_url": "https://github.com/o/r/pull/104"
  },
  "comment": {
    "id": 202,
    "html_url": "https://github.com/o/r/pull/104#discussion_r202",
    "body": "human",
    "user": {"login": "octocat"}
  }
}
EOF

event_inline_bot="$tmpdir/event-inline-bot.json"
cat > "$event_inline_bot" <<'EOF'
{
  "pull_request": {
    "number": 104,
    "html_url": "https://github.com/o/r/pull/104"
  },
  "comment": {
    "id": 404,
    "html_url": "https://github.com/o/r/pull/104#discussion_r404",
    "body": "please fix inline",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

event_review_empty="$tmpdir/event-review-empty.json"
cat > "$event_review_empty" <<'EOF'
{
  "pull_request": {
    "number": 104,
    "html_url": "https://github.com/o/r/pull/104"
  },
  "review": {
    "id": 304,
    "html_url": "https://github.com/o/r/pull/104#pullrequestreview-304",
    "body": "",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

event_review="$tmpdir/event-review.json"
cat > "$event_review" <<'EOF'
{
  "pull_request": {
    "number": 104,
    "html_url": "https://github.com/o/r/pull/104"
  },
  "review": {
    "id": 303,
    "html_url": "https://github.com/o/r/pull/104#pullrequestreview-303",
    "body": "nit",
    "user": {"login": "coderabbitai[bot]"}
  }
}
EOF

event_issue_failpush="$tmpdir/event-issue-failpush.json"
cat > "$event_issue_failpush" <<'EOF'
{
  "issue": {
    "number": 104,
    "pull_request": {"url": "https://api.github.com/repos/o/r/pulls/104"}
  },
  "comment": {
    "id": 909,
    "html_url": "https://github.com/o/r/pull/104#issuecomment-909",
    "body": "please fail push path",
    "user": {"login": "chatgpt-codex-connector[bot]"}
  }
}
EOF

export PATH="$tmpdir/bin:$PATH"
export GH_STUB_LOG="$tmpdir/gh.log"
export GH_STUB_COMMENTS="$tmpdir/comments.log"
export GH_STUB_HEAD_REPO="o/r"
export GH_STUB_HEAD_REF="feature/test-autofix"
export GH_STUB_BASE_REF="develop"
export GH_TOKEN=dummy
export GITHUB_REPOSITORY=o/r
export GITHUB_RUN_ID=12345
export AGENTIC_SDD_AUTOFIX_CMD=./scripts/mock-autofix.sh
export AGENTIC_SDD_AUTOFIX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]'
export AGENTIC_SDD_AUTOFIX_OPTIN_LABEL='autofix-enabled'
export AGENTIC_SDD_AUTOFIX_MAX_ITERS=10

unset AGENTIC_SDD_PR_REVIEW_MENTION
out_missing_mention="$tmpdir/out-missing-mention.txt"
set +e
( cd "$work" && GITHUB_EVENT_PATH="$event_issue" bash ./scripts/agentic-sdd-pr-autofix.sh ) >"$out_missing_mention" 2>&1
rc_missing_mention=$?
set -e
if [[ "$rc_missing_mention" -eq 0 ]]; then
  eprint "Expected missing review mention configuration to fail"
  exit 1
fi
if ! grep -Fq "Missing AGENTIC_SDD_PR_REVIEW_MENTION" "$out_missing_mention"; then
  eprint "Expected missing mention error message"
  exit 1
fi

export AGENTIC_SDD_PR_REVIEW_MENTION='@pr-bots review'
unset AGENTIC_SDD_AUTOFIX_BOT_LOGINS
out_missing_allowlist="$tmpdir/out-missing-allowlist.txt"
set +e
( cd "$work" && GITHUB_EVENT_PATH="$event_issue" bash ./scripts/agentic-sdd-pr-autofix.sh ) >"$out_missing_allowlist" 2>&1
rc_missing_allowlist=$?
set -e
if [[ "$rc_missing_allowlist" -eq 0 ]]; then
  eprint "Expected missing autofix allowlist to fail"
  exit 1
fi
if ! grep -Fq "Missing AGENTIC_SDD_AUTOFIX_BOT_LOGINS" "$out_missing_allowlist"; then
  eprint "Expected missing allowlist error message"
  exit 1
fi

export AGENTIC_SDD_AUTOFIX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]'
export AGENTIC_SDD_AUTOFIX_MAX_ITERS=1
( cd "$work" && GITHUB_EVENT_PATH="$event_issue" bash ./scripts/agentic-sdd-pr-autofix.sh )
export AGENTIC_SDD_AUTOFIX_MAX_ITERS=10

if [[ "$(cat "$work/.event_type")" != "issue_comment" ]]; then
  eprint "Expected issue_comment event type"
  exit 1
fi

if ! grep -Fq "@pr-bots review" "$tmpdir/comments.log"; then
  eprint "Expected configured review mention after push"
  exit 1
fi

pushed_sha_1="$(git -C "$work" rev-parse HEAD)"
if ! grep -Fq "head SHA ($pushed_sha_1)" "$tmpdir/comments.log"; then
  eprint "Expected review mention comment to include current head SHA"
  exit 1
fi
if ! grep -Fq "ベースブランチ develop" "$tmpdir/comments.log"; then
  eprint "Expected review mention comment to include PR base branch"
  exit 1
fi

if ! grep -Fq "Source event: issue_comment:101:" "$tmpdir/comments.log"; then
  eprint "Expected source event key for issue_comment"
  exit 1
fi

comments_before="$(wc -l < "$tmpdir/comments.log")"
( cd "$work" && GITHUB_EVENT_PATH="$event_issue" bash ./scripts/agentic-sdd-pr-autofix.sh )
comments_after="$(wc -l < "$tmpdir/comments.log")"
if [[ "$comments_before" != "$comments_after" ]]; then
  eprint "Expected duplicate event to be skipped"
  exit 1
fi

( cd "$work" && GITHUB_EVENT_PATH="$event_inline_nonbot" bash ./scripts/agentic-sdd-pr-autofix.sh )
if [[ "$(wc -l < "$tmpdir/comments.log")" != "$comments_after" ]]; then
  eprint "Expected non-bot event to no-op without comments"
  exit 1
fi

comments_before_inline_bot="$(wc -l < "$tmpdir/comments.log")"
( cd "$work" && GITHUB_EVENT_PATH="$event_inline_bot" bash ./scripts/agentic-sdd-pr-autofix.sh )
comments_after_inline_bot="$(wc -l < "$tmpdir/comments.log")"
if [[ "$comments_after_inline_bot" -le "$comments_before_inline_bot" ]]; then
  eprint "Expected bot inline event to produce a new comment"
  exit 1
fi
if [[ "$(cat "$work/.event_type")" != "inline" ]]; then
  eprint "Expected inline event type"
  exit 1
fi
if ! grep -Fq "Source event: inline:404:" "$tmpdir/comments.log"; then
  eprint "Expected source event key for inline bot event"
  exit 1
fi

comments_before_empty_review="$(wc -l < "$tmpdir/comments.log")"
( cd "$work" && GITHUB_EVENT_PATH="$event_review_empty" bash ./scripts/agentic-sdd-pr-autofix.sh )
comments_after_empty_review="$(wc -l < "$tmpdir/comments.log")"
if [[ "$comments_after_empty_review" != "$comments_before_empty_review" ]]; then
  eprint "Expected empty review body event to no-op without comments"
  exit 1
fi

( cd "$work" && GITHUB_EVENT_PATH="$event_review" bash ./scripts/agentic-sdd-pr-autofix.sh )
if [[ "$(cat "$work/.event_type")" != "review" ]]; then
  eprint "Expected review event type"
  exit 1
fi

if ! grep -Fq "Source event: review:303:" "$tmpdir/comments.log"; then
  eprint "Expected source event key for review"
  exit 1
fi

cat > "$remote/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$remote/hooks/pre-receive"

( cd "$work" && GITHUB_EVENT_PATH="$event_issue_failpush" bash ./scripts/agentic-sdd-pr-autofix.sh )
if ! grep -Fq "Autofix produced changes but could not push" "$tmpdir/comments.log"; then
  eprint "Expected push-failure comment"
  exit 1
fi
if ! grep -Fq "Target SHA:" "$tmpdir/comments.log"; then
  eprint "Expected failure output to include target SHA"
  exit 1
fi
if ! grep -Fq "Run: https://github.com/o/r/actions/runs/12345" "$tmpdir/comments.log"; then
  eprint "Expected failure output to include run URL"
  exit 1
fi
if ! grep -Fq "Source event: issue_comment:909:" "$tmpdir/comments.log"; then
  eprint "Expected failure output to include source event key"
  exit 1
fi

rm -f "$remote/hooks/pre-receive"
comments_before_retry="$(wc -l < "$tmpdir/comments.log")"
( cd "$work" && GITHUB_EVENT_PATH="$event_issue_failpush" bash ./scripts/agentic-sdd-pr-autofix.sh )
comments_after_retry="$(wc -l < "$tmpdir/comments.log")"
if [[ "$comments_after_retry" -le "$comments_before_retry" ]]; then
  eprint "Expected retry after failed source event to proceed"
  exit 1
fi

eprint "OK: scripts/tests/test-pr-autofix-template.sh"
