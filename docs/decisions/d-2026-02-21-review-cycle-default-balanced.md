# Decision: review-cycle の再利用ポリシー既定値を balanced に変更

## Decision-ID

D-2026-02-21-REVIEW_CYCLE_DEFAULT_BALANCED

## Context

- 背景: Issue #117 で `REVIEW_CYCLE_CACHE_POLICY` の既定値を `strict` から `balanced` へ変更する要件が確定した。
- どの矛盾/制約を解決するか: 同一 fingerprint の `Blocked` / `Question` 再実行で毎回フルレビューになる運用コストと、Issue #109 が狙った再利用効果の不足を解消する。

## Rationale

- なぜこの決定を採用したか:
  - 無変更ループで `Blocked` / `Question` も再利用対象に含めることで、LLM実行コストを削減できるため。
  - 入力が同一なのに結果が揺れるケースを抑え、再現性の高いレビュー運用に寄与するため。
  - `strict` / `off` の明示指定は維持し、より保守的な運用を選べる後方互換を保つため。
- SoT（PRD/Epic/Issue）との整合:
  - PRD/Epic が定める「既存コマンド全面置換は原則禁止、必要な範囲の運用改善はIssue単位で反映」の方針に沿って、既存機能を壊さず既定値のみを更新している。

## Alternatives

### Alternative-A: 既定値を strict のまま維持

- 採用可否: No
- Pros:
  - 非承認結果を自動再利用しないため、より保守的な運用になる。
- Cons:
  - 同一入力の `Blocked` / `Question` ループで毎回フル実行となり、コスト削減効果が限定される。

### Alternative-B: 既定値を off にして常時フル実行

- 採用可否: No
- Pros:
  - 再利用判定による挙動差分がなく、常に同一実行経路になる。
- Cons:
  - 再利用の利点を完全に失い、運用コストが増える。

## Impact

- 影響範囲:
  - `scripts/agentic-sdd/review-cycle.sh`（既定値変更）
  - `.agent/commands/review-cycle.md` / `README.md`（運用ガイド同期）
  - `scripts/agentic-sdd/tests/test-review-cycle.sh`（既定挙動の期待値更新）
- 互換性:
  - `REVIEW_CYCLE_CACHE_POLICY=strict|off` の明示指定は継続サポートし、後方互換を維持する。
- 運用影響:
  - 既定で `Blocked` / `Question` の no-change 再実行が再利用される。
  - `/final-review` 前に fresh full を明示実行するガイドは維持する。

## Verification

- 検証方法:
  - `bash scripts/agentic-sdd/tests/test-review-cycle.sh`
  - `TEST_REVIEW_PREFLIGHT_COMMAND='bash scripts/agentic-sdd/tests/test-review-cycle.sh' TEST_REVIEW_DIFF_MODE=worktree ./scripts/agentic-sdd/test-review.sh issue-117`
  - `GH_ISSUE=117 DIFF_MODE=worktree TEST_COMMAND='bash scripts/agentic-sdd/tests/test-review-cycle.sh' ./scripts/agentic-sdd/review-cycle.sh issue-117`
- エビデンス:
  - `scripts/agentic-sdd/review-cycle.sh:324` で既定値が `balanced` になっている。
  - `scripts/agentic-sdd/tests/test-review-cycle.sh:642` / `scripts/agentic-sdd/tests/test-review-cycle.sh:648` で既定挙動期待値を更新済み。
  - `scripts/agentic-sdd/tests/test-review-cycle.sh:744` / `scripts/agentic-sdd/tests/test-review-cycle.sh:821` で `strict` / `off` の明示指定互換を維持。

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: `docs/prd/agentic-sdd-harness-engineering.md:60`
- Epic: `docs/epics/agentic-sdd-harness-engineering.md:39`
- Issue: `https://github.com/ToaruPen/Agentic-SDD/issues/117`
- Related files:
  - `scripts/agentic-sdd/review-cycle.sh`
  - `.agent/commands/review-cycle.md`
  - `README.md`
  - `scripts/agentic-sdd/tests/test-review-cycle.sh`
