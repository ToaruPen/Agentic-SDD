# /codex-pr-review

Request a Codex bot review on a GitHub Pull Request and iterate until resolved.

This command mirrors the OpenCode global skill `codex-pr-review` (located under
`~/.config/opencode/skills/codex-pr-review/`).

User-facing output remains in Japanese.

## Usage

```text
/codex-pr-review <PR_NUMBER_OR_URL>
```

## Flow

### Phase 0: Preconditions (fail-fast)

Required:

1. `gh` (GitHub CLI) is authenticated for the target repo.
2. The PR exists and is pushed.

### Phase 1: Request Codex review

1. Capture the current head SHA:

```bash
HEAD_SHA="$(git rev-parse HEAD)"
echo "$HEAD_SHA"
```

2. Comment `@codex review` on the PR (include the head SHA so the bot reviews the current PR state):

```bash
gh pr comment <PR_NUMBER_OR_URL> --body "$(cat <<EOF
@codex review

Please review the entire PR as a diff from the base branch (main), not a single commit.

Focus on the current PR state (head SHA: ${HEAD_SHA}).
Review all files changed in the PR and any relevant surrounding context.
Call out only actionable issues; avoid repeating already-fixed items.
EOF
)"
```

Notes:

- Use exactly `@codex review`.
- If the PR is a draft, request review after marking it ready.

### Phase 2: Fetch Codex feedback

Codex may post:

- conversation comments (PR timeline)
- inline review comments (attached to files/lines)
- reviews summary

```bash
# Conversation comments
gh api repos/<OWNER>/<REPO>/issues/<PR_NUMBER>/comments \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {created_at, body}'

# Inline review comments
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {created_at, path, line, body}'

# Reviews summary
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {submitted_at, state, body}'
```

If `gh pr view <PR> --comments` is available and sufficient, you can use it for a quick scan.

### Phase 3: Apply fixes and verify

- Only fix issues introduced by the PR.
- Keep changes minimal; avoid opportunistic refactors.
- Run the repo's standard checks (typecheck/lint/test/build/coverage) before pushing.

### Phase 4: Push and re-request review

After pushing fixes, re-request review (again include the current head SHA):

```bash
git push

HEAD_SHA="$(git rev-parse HEAD)"

gh pr comment <PR_NUMBER_OR_URL> --body "$(cat <<EOF
@codex review

Please re-review the PR as a diff from the base branch (main), focusing on the current head SHA (${HEAD_SHA}).

Only call out actionable issues that remain in the current PR state; avoid repeating already-fixed items.
EOF
)"
```

## Exit condition

Stop when:

1. Codex provides no further actionable findings.
2. CI is green.
3. Human review requirements (if any) are satisfied.

