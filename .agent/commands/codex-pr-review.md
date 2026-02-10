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

2. Comment `@codex review` on the PR (include the head SHA so the bot reviews the current PR state).
The comment body should be Japanese, but keep `@codex review` exactly as-is.

```bash
gh pr comment <PR_NUMBER_OR_URL> --body "$(cat <<EOF
@codex review

このPRを、ベースブランチ（main）との差分としてレビューしてください（単一コミットではなくPR全体のdiffとして）。

対象は現時点のPR状態です（head SHA: ${HEAD_SHA}）。
変更された全ファイルと、必要に応じて周辺コンテキストも確認してください。
指摘は「今このPRに対して実行可能なもの」だけに絞り、既に解消済みの事項の繰り返しは避けてください。
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

このPRを再レビューしてください（ベースブランチ main との差分として）。対象は現時点の head SHA (${HEAD_SHA}) です。

現時点のPRに残っている「実行可能な指摘」だけを挙げ、既に解消済みの事項の繰り返しは避けてください。
EOF
)"
```

## Exit condition

Stop when:

1. Codex provides no further actionable findings.
2. CI is green.
3. Human review requirements (if any) are satisfied.
