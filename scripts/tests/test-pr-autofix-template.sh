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
optin_label="${GH_STUB_OPTIN_LABEL:-autofix-enabled}"

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
      if [[ -f "$comments_file" ]]; then
        cat "$comments_file"
      fi
      exit 0
    fi
    body=""
    for arg in "$@"; do
      case "$arg" in
        body=*) body="${arg#body=}" ;;
      esac
    done
    printf '%s\n' "$body" >> "$comments_file"
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

export PATH="$tmpdir/bin:$PATH"
export GH_STUB_LOG="$tmpdir/gh.log"
export GH_STUB_COMMENTS="$tmpdir/comments.log"
export GH_STUB_HEAD_REPO="o/r"
export GH_STUB_HEAD_REF="feature/test-autofix"
export GH_TOKEN=dummy
export GITHUB_REPOSITORY=o/r
export GITHUB_RUN_ID=12345
export AGENTIC_SDD_AUTOFIX_CMD=./scripts/mock-autofix.sh
export AGENTIC_SDD_AUTOFIX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]'
export AGENTIC_SDD_AUTOFIX_OPTIN_LABEL='autofix-enabled'

( cd "$work" && GITHUB_EVENT_PATH="$event_issue" bash ./scripts/agentic-sdd-pr-autofix.sh )

if [[ "$(cat "$work/.event_type")" != "issue_comment" ]]; then
  eprint "Expected issue_comment event type"
  exit 1
fi

if ! grep -Fq "@codex review" "$tmpdir/comments.log"; then
  eprint "Expected @codex review comment after push"
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

( cd "$work" && GITHUB_EVENT_PATH="$event_review" bash ./scripts/agentic-sdd-pr-autofix.sh )
if [[ "$(cat "$work/.event_type")" != "review" ]]; then
  eprint "Expected review event type"
  exit 1
fi

if ! grep -Fq "Source event: review:303:" "$tmpdir/comments.log"; then
  eprint "Expected source event key for review"
  exit 1
fi

eprint "OK: scripts/tests/test-pr-autofix-template.sh"
