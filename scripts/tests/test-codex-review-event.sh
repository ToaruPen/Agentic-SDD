#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="$repo_root/scripts/codex-review-event.sh"

if [[ ! -x "$script_path" ]]; then
  eprint "Missing script or not executable: $script_path"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t codex-review-event-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

mkdir -p "$tmpdir/bin"

cat > "$tmpdir/bin/gh-ok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$tmpdir/bin/gh-ok"

cat > "$tmpdir/bin/gh-fail" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$tmpdir/bin/gh-fail"

cat > "$tmpdir/issue_comment.json" <<'EOF'
{
  "issue": {
    "number": 103,
    "html_url": "https://github.com/o/r/pull/103",
    "pull_request": {
      "url": "https://api.github.com/repos/o/r/pulls/103"
    }
  },
  "comment": {
    "body": "Please fix style and tests.",
    "user": {
      "login": "chatgpt-codex-connector[bot]"
    }
  }
}
EOF

cat > "$tmpdir/issue_comment_non_pr.json" <<'EOF'
{
  "issue": {
    "number": 999,
    "html_url": "https://github.com/o/r/issues/999"
  },
  "comment": {
    "body": "status update",
    "user": {
      "login": "chatgpt-codex-connector[bot]"
    }
  }
}
EOF

cat > "$tmpdir/review_comment_non_bot.json" <<'EOF'
{
  "pull_request": {
    "number": 104,
    "html_url": "https://github.com/o/r/pull/104"
  },
  "comment": {
    "body": "human comment",
    "user": {
      "login": "octocat"
    }
  }
}
EOF

cat > "$tmpdir/review.json" <<'EOF'
{
  "pull_request": {
    "number": 105,
    "html_url": "https://github.com/o/r/pull/105"
  },
  "review": {
    "body": "nit: rename variable",
    "user": {
      "login": "coderabbitai[bot]"
    }
  }
}
EOF

out1="$tmpdir/out1.txt"
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$tmpdir/issue_comment.json" CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' CODEX_REVIEW_REQUIRE_GH_AUTH=0 bash "$script_path" >"$out1" 2>&1
if ! grep -Fq 'type=issue pr_number=103 pr_url=https://github.com/o/r/pull/103' "$out1"; then
  eprint "Expected normalized issue event output"
  exit 1
fi
if ! grep -Fq 'snippet=Please fix style and tests.' "$out1"; then
  eprint "Expected snippet output for issue event"
  exit 1
fi

out2="$tmpdir/out2.txt"
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=pull_request_review_comment GITHUB_EVENT_PATH="$tmpdir/review_comment_non_bot.json" CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' CODEX_REVIEW_REQUIRE_GH_AUTH=0 bash "$script_path" >"$out2" 2>&1
if ! grep -Fq 'no-op: actor not in CODEX_BOT_LOGINS (actor=octocat)' "$out2"; then
  eprint "Expected non-allowlisted actor no-op message"
  exit 1
fi

out2b="$tmpdir/out2b.txt"
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$tmpdir/issue_comment_non_pr.json" CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' CODEX_REVIEW_REQUIRE_GH_AUTH=0 bash "$script_path" >"$out2b" 2>&1
if ! grep -Fq 'no-op: issue_comment is not on a pull request' "$out2b"; then
  eprint "Expected non-PR issue_comment no-op message"
  exit 1
fi

out3="$tmpdir/out3.txt"
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=pull_request_review GITHUB_EVENT_PATH="$tmpdir/review.json" CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' CODEX_REVIEW_REQUIRE_GH_AUTH=0 bash "$script_path" >"$out3" 2>&1
if ! grep -Fq 'type=review pr_number=105 pr_url=https://github.com/o/r/pull/105' "$out3"; then
  eprint "Expected normalized review event output"
  exit 1
fi

set +e
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$tmpdir/issue_comment.json" CODEX_REVIEW_REQUIRE_GH_AUTH=0 bash "$script_path" >"$tmpdir/out3b.txt" 2>&1
rc_missing_allowlist=$?
set -e
if [[ "$rc_missing_allowlist" -eq 0 ]]; then
  eprint "Expected missing CODEX_BOT_LOGINS to fail"
  exit 1
fi
if ! grep -Fq 'error: CODEX_BOT_LOGINS is required' "$tmpdir/out3b.txt"; then
  eprint "Expected missing allowlist error message"
  exit 1
fi

ln -sf "$tmpdir/bin/gh-fail" "$tmpdir/bin/gh"
set +e
PATH="$tmpdir/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$tmpdir/issue_comment.json" CODEX_BOT_LOGINS='chatgpt-codex-connector[bot],coderabbitai[bot]' CODEX_REVIEW_REQUIRE_GH_AUTH=1 bash "$script_path" >"$tmpdir/out4.txt" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  eprint "Expected auth failure path to exit non-zero"
  exit 1
fi
if ! grep -Fq 'error: GitHub authentication failed.' "$tmpdir/out4.txt"; then
  eprint "Expected auth failure message"
  exit 1
fi

eprint "test-codex-review-event: ok"
