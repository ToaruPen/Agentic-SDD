# Decision: Ruff S ルール段階導入と例外運用

## Decision-ID

D-2026-02-18-RUFF_S_RULE_ROLLOUT

## Context

- Issue #86 で `ruff check . --select S` の段階導入を進める必要があった
- 既存スクリプトの `subprocess` 実行と例外処理に起因する違反（S112/S603/S607）が検出された

## Rationale

- 既存動作を壊さずに fail-closed 運用へ移行するため、最小修正を優先した
- 過剰なリファクタを避け、Issueスコープを超えない実装を採用した

## Alternatives

### Alternative-A: すべてコード置換で解消し、noqaを禁止

- 採用可否: No
- Pros: ルールが単純で監査しやすい
- Cons: 実行コマンドが固定で安全な箇所まで大きく改修が必要

### Alternative-B: 最小修正 + 明示的な例外注釈

- 採用可否: Yes
- Pros: 既存動作を維持しつつ段階導入できる
- Cons: 例外管理を継続運用する必要がある

## Impact

- 新規/変更で `# noqa: S603` を追加する場合は、該当行に限定し、実行引数が固定であることを前提にする
- `S112/S110` は握りつぶしを避け、具体例外の捕捉または分岐で解消する
- CI/ローカルで `ruff check . --select S` を継続実行する

## Verification

- 検証方法: `ruff check . --select S` の実行結果と差分レビュー
- エビデンス: Issue #86 の実装差分と調査メモ

## Supersedes

- N/A

## Inputs Fingerprint

- PRD: N/A（本Decisionは静的検査導入Issueの運用判断）
- Epic: N/A（本DecisionはIssue実装判断）
- Issue: #86
- Related files: `scripts/*.py`, `docs/research/estimation/issue-86/2026-02-18.md`
