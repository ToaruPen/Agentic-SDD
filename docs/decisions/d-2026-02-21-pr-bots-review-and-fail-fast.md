# Decision: pr-bots-review への刷新と fail-fast 必須化

## Decision-ID

D-2026-02-21-PR_BOTS_REVIEW_AND_FAIL_FAST

## Context

- 背景: Issue #108 で `/codex-pr-review` を `/pr-bots-review` に刷新し、レビューBot設定を外部化する要件が確定。
- どの矛盾/制約を解決するか: PRD の「互換性を壊す全面置換は対象外」と、Issue #108 の「aliasなし全面刷新」の矛盾を、例外スコープとして明文化して解消する。

## Rationale

- なぜこの決定を採用したか:
  - 運用導線を `/pr-bots-review` に一本化し、Bot 固有名に依存しない設計へ移行するため。
  - `AGENTIC_SDD_PR_REVIEW_MENTION` と allowlist の未設定を fail-fast に統一し、設定ミスを早期に可観測化するため。
- SoT（PRD/Epic/Issue）との整合:
  - PRD/Epic に Issue #108 例外を追記し、実装済み方針と整合済み。

## Alternatives

### Alternative-A: 旧コマンドを alias で残す

- 採用可否: No
- Pros:
  - 既存利用者への影響を最小化できる。
- Cons:
  - Issue #108 の受け入れ条件（aliasなし）に反する。
  - docs/生成経路で二重導線が残り、運用が複雑化する。

### Alternative-B: allowlist/mention 未設定時は warn して no-op

- 採用可否: No
- Pros:
  - 既存設定なし環境で突然失敗しない。
- Cons:
  - 設定漏れを見逃しやすく、AC3 の fail-fast 要件に反する。

## Impact

- 影響範囲:
  - コマンド導線（`.agent/commands`, `README.md`, `AGENTS.md`）
  - review-loop/autofix-loop 実装（`scripts/`, `templates/`）
  - 関連テスト（`scripts/tests/`）
- 互換性:
  - 旧 `/codex-pr-review` 導線は廃止（互換非維持）。
- 運用影響:
  - `AGENTIC_SDD_PR_REVIEW_MENTION` と allowlist 未設定時は即時失敗し、設定不足を明確に通知する。

## Verification

- 検証方法:
  - `bash scripts/tests/test-pr-autofix-template.sh`
  - `bash scripts/tests/test-codex-review-event.sh`
  - `python3 scripts/lint-sot.py docs`
  - `GH_ISSUE=108 DIFF_MODE=staged TEST_COMMAND='bash scripts/tests/test-pr-autofix-template.sh && bash scripts/tests/test-codex-review-event.sh' ./scripts/review-cycle.sh issue-108`
- エビデンス:
  - 未設定 fail-fast のテストケース追加（mention/allowlist）
  - review-cycle status `Approved` の確認

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: `docs/prd/agentic-sdd-harness-engineering.md:55`
- Epic: `docs/epics/agentic-sdd-harness-engineering.md:36`
- Issue: `https://github.com/ToaruPen/Agentic-SDD/issues/108`
- Related files:
  - `.agent/commands/pr-bots-review.md`
  - `templates/ci/github-actions/scripts/agentic-sdd-pr-autofix.sh`
  - `scripts/codex-review-event.sh`
  - `scripts/watch-codex-review.sh`
  - `scripts/tests/test-pr-autofix-template.sh`
  - `scripts/tests/test-codex-review-event.sh`
