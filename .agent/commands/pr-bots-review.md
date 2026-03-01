# /pr-bots-review

Request a review-bot check on a GitHub Pull Request and iterate until resolved.

Autonomous default policy:

- After `/create-pr`, run `/pr-bots-review` as the default next step when review-bot configuration is present (`AGENTIC_SDD_PR_REVIEW_MENTION` plus bot login filtering settings).
- If event-driven autofix is configured, treat this command as the verification/control loop while automation handles routine bot feedback.

User-facing output remains in Japanese.

## Usage

```text
/pr-bots-review <PR_NUMBER_OR_URL>
```

## Flow

### Phase 0: Preconditions (fail-fast)

Required:

1. `gh` (GitHub CLI) is authenticated for the target repo.
2. The PR exists and is pushed.
3. Scope Lock verification is completed:
   - Confirm current branch: `git branch --show-current`
   - For Issue-scoped work, list linked branches: `gh issue develop --list <issue-number>`
   - Confirm PR head branch: `gh pr view <pr-number-or-url> --json headRefName --jq '.headRefName'`
   - If current branch and PR `headRefName` differ, stop and switch to the correct branch.
4. `AGENTIC_SDD_PR_REVIEW_MENTION` is set.
5. For Phase 2 bot filtering, either `CODEX_BOT_LOGINS` is set or `BOT_LOGIN` is
   provided manually.

### Phase 1: Request review-bot check

1. Capture the current head SHA:

```bash
HEAD_SHA="$(git rev-parse HEAD)"
echo "$HEAD_SHA"
```

1. Resolve review mention from `AGENTIC_SDD_PR_REVIEW_MENTION` and comment it on the PR
   (include the head SHA so the bot reviews the current PR state).
   The comment body should be Japanese.

```bash
REVIEW_MENTION="${AGENTIC_SDD_PR_REVIEW_MENTION:?AGENTIC_SDD_PR_REVIEW_MENTION is required}"

gh pr comment <PR_NUMBER_OR_URL> --body "$(cat <<EOF
${REVIEW_MENTION}

このPRを、ベースブランチ（main）との差分としてレビューしてください（単一コミットではなくPR全体のdiffとして）。

対象は現時点のPR状態です（head SHA: ${HEAD_SHA}）。
変更された全ファイルと、必要に応じて周辺コンテキストも確認してください。
指摘は「今このPRに対して実行可能なもの」だけに絞り、既に解消済みの事項の繰り返しは避けてください。
EOF
)"
```

Notes:

- `AGENTIC_SDD_PR_REVIEW_MENTION` is required.
- If the PR is a draft, request review after marking it ready.

### Phase 2: Fetch review-bot feedback

Use event-driven workflows as the default operating mode.
If your repository has `.github/workflows/codex-review-events.yml`, use it for notification/observability.
For CI-based autofix loops, use
`templates/ci/github-actions/.github/workflows/agentic-sdd-pr-autofix.yml`.

Review bot may post:

- conversation comments (PR timeline)
- inline review comments (attached to files/lines)
- reviews summary

Before running the API queries below, set `BOT_LOGIN`.
If `CODEX_BOT_LOGINS` is set, extract one login from that comma-separated list.
If not, set `BOT_LOGIN` manually.

```bash
if [ -n "${CODEX_BOT_LOGINS:-}" ]; then
  BOT_LOGIN="${CODEX_BOT_LOGINS%%,*}"
else
  BOT_LOGIN="<actual-bot-login>"
fi

echo "$BOT_LOGIN"
```

```bash
# Conversation comments
gh api repos/<OWNER>/<REPO>/issues/<PR_NUMBER>/comments \
  --jq ".[] | select(.user.login==\"${BOT_LOGIN}\") | {created_at, body}"

# Inline review comments
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments \
  --jq ".[] | select(.user.login==\"${BOT_LOGIN}\") | {created_at, path, line, body}"

# Reviews summary
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews \
  --jq ".[] | select(.user.login==\"${BOT_LOGIN}\") | {submitted_at, state, body}"
```

Note: The CI autofix implementation resolves PR metadata with a single
`fetch_pr_metadata()` call (`gh pr view --json headRepository,headRefName,baseRefName`).
The individual commands above are kept for manual/debugging usage only.

If you prefer manual inline replacement, replace `<actual-bot-login>` with the
concrete bot login before running the queries.

If `gh pr view <PR> --comments` is available and sufficient, you can use it for a quick scan.


### Phase 2.5: Parse review body for embedded comments (Nitpick / AI prompt)

CodeRabbit (and similar bots) use a 2-tier feedback structure:

| Tier       | Type                         | Location                                              | API                     | `isResolved` tracking |
| ---------- | ---------------------------- | ----------------------------------------------------- | ----------------------- | --------------------- |
| **Tier 1** | Actionable comments (inline) | PR line comments → threaded                           | GraphQL `reviewThreads` | ✅ Yes                |
| **Tier 2** | Nitpick comments             | Review body `<details>🧹 Nitpick comments</details>` | `reviews.body` parsing  | ❌ No                 |

Phase 2 covers Tier 1. This phase covers Tier 2 and the AI agent prompt section.

**Important**: Do NOT truncate `reviews.body` (e.g. `.body[0:300]`). The full body is required
for reliable section parsing.

#### Step 1: Fetch full review body with Nitpick sections

Note: The jq filter uses `env.BOT_LOGIN`, which requires the variable to be exported.
If Phase 2 set `BOT_LOGIN` without `export`, run `export BOT_LOGIN` first.

```bash
# Get bot reviews containing Nitpick or AI agent prompt sections (full body, no truncation)
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(last: 50) {
          nodes {
            author { login }
            submittedAt
            body
          }
        }
      }
    }
  }
' -f owner="<OWNER>" -f repo="<REPO>" -F pr=<PR_NUMBER> \
  --jq '
    .data.repository.pullRequest.reviews.nodes[]
    | select(.author.login == env.BOT_LOGIN)
    | select(.body | test("Nitpick|🧹|🤖 Prompt"))
    | {submitted: .submittedAt, body: .body}
  '
```

Note: `last: 50` retrieves the most recent 50 reviews, which is sufficient for typical PRs.
For high-activity PRs with more than 50 reviews, use GraphQL pagination (`pageInfo` / `before` cursor)
to ensure all bot review bodies are fetched.

#### Step 2: Parse and list Nitpick comments

From the review body, extract all items inside `<details>` blocks matching `🧹 Nitpick comments`:

- List each Nitpick separately with file path and description.
- Present them as a distinct list from Tier 1 inline comments.
- For each Nitpick, decide: **fix**, **acknowledge (won't fix + reason)**, or **defer (create Issue)**.

Since Nitpick comments have no `isResolved` tracking, record the disposition
(fixed / acknowledged / deferred) as a PR comment for auditability.

#### Step 3: Check AI agent prompt section

Review body may also contain a `<details>🤖 Prompt for all review comments with AI agents</details>` section.
This section aggregates Tier 1 + Tier 2 comments in a format optimized for AI agent consumption.

- Use this section as a cross-reference to verify all feedback (inline + nitpick) has been addressed.
- Do NOT treat this section as the primary source — always parse Tier 1 (inline) and Tier 2 (nitpick) separately first.

### Phase 3: Apply fixes and verify

- Only fix issues introduced by the PR.
- Keep changes minimal; avoid opportunistic refactors.
- Run the repo's standard checks (typecheck/lint/test/build/coverage) before pushing.

### Phase 4: Push and re-request review

When using the CI template `agentic-sdd-pr-autofix.yml`, this step can be automated by
the installed target-repo script `scripts/agentic-sdd/agentic-sdd-pr-autofix.sh`
(source template: `templates/ci/github-actions/scripts/agentic-sdd-pr-autofix.sh`) after successful autofix push.

After pushing fixes, re-request review (again include the current head SHA):

```bash
git push

HEAD_SHA="$(git rev-parse HEAD)"
REVIEW_MENTION="${AGENTIC_SDD_PR_REVIEW_MENTION:?AGENTIC_SDD_PR_REVIEW_MENTION is required}"

gh pr comment <PR_NUMBER_OR_URL> --body "$(cat <<EOF
${REVIEW_MENTION}

このPRを再レビューしてください（ベースブランチ main との差分として）。対象は現時点の head SHA (${HEAD_SHA}) です。

現時点のPRに残っている「実行可能な指摘」だけを挙げ、既に解消済みの事項の繰り返しは避けてください。
EOF
)"
```

Notes:

- `AGENTIC_SDD_PR_REVIEW_MENTION` is required in this phase as well.

## Exit condition

Stop when:

1. The configured review bot provides no further actionable findings.
2. CI is green.
3. Human review requirements (if any) are satisfied.

## Related

- `.agent/rules/runtime-controls.md` - prompt caching/compaction/context management runbook
- `.agent/commands/create-pr.md` - PR creation gate and metadata checks
