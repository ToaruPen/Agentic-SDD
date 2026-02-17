# /test-review

実装完了後のテストレビューを二段構成で実行する。

1) 前段フィルタ（機械判定）
2) 後段品質チェック（機械判定の追加ヒューリスティクス）

このコマンドは `review.json` の代替ではない。`/review-cycle` 前段で無駄な再レビューを減らすための fail-fast ゲートとして使う。

## Usage

```text
/test-review <scope-id> [run-id]
```

実体:

```bash
./scripts/test-review.sh <scope-id> [run-id]
```

## Required environment

- `TEST_REVIEW_PREFLIGHT_COMMAND` (必須)
  - 例: `bash scripts/tests/test-ruff-gate.sh && bash scripts/tests/test-ruff-format-gate.sh && bash scripts/tests/test-lint-sot.sh`

## Optional environment

- `TEST_REVIEW_DIFF_MODE` = `auto|worktree|staged|range`（default: `auto`）
- `TEST_REVIEW_BASE_REF`（`range` 用。default: `origin/main`）
- `OUTPUT_ROOT`（default: `<repo>/.agentic-sdd/test-reviews`）

## Output

- `.agentic-sdd/test-reviews/<scope-id>/<run-id>/test-review.json`
- `.agentic-sdd/test-reviews/<scope-id>/<run-id>/test-review-metadata.json`
- `.agentic-sdd/test-reviews/<scope-id>/<run-id>/preflight.txt`
- `.agentic-sdd/test-reviews/<scope-id>/<run-id>/diff-files.txt`

## Status handling

- `Approved`: 通過
- `Blocked`: fail-fast（前段コマンド失敗、focused test marker、コード変更に対するテスト変更不足）

## PR gate note

- コミット前（`/impl`・`/tdd` のローカル確認）では `auto` / `worktree` / `staged` を使ってよい。
- `/create-pr` 前には、コミット済み `HEAD` に対して `TEST_REVIEW_DIFF_MODE=range` で `/test-review` を再実行する。

## Related

- `.agent/commands/review-cycle.md` - ローカルレビュー本体
- `.agent/commands/impl.md` - 実装フロー
- `.agent/commands/tdd.md` - TDDフロー
- `.agent/commands/create-pr.md` - PR作成ゲート
