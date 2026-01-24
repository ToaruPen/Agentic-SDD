# /review-cycle

開発中にローカルで「レビュー(JSON) → 修正 → 再レビュー(JSON)」を反復するためのコマンド。

このコマンドは `codex exec` を使って `review.json`（レビュー結果JSON）を生成する。

最終ゲートは従来通り `/review`（DoD + `/sync-docs`）で行う。

## 使用方法

```
/review-cycle <scope-id> [run-id]
```

- `scope-id`: `issue-123` のような識別子（`[A-Za-z0-9._-]+`）
- `run-id`: 省略時は `.agentic-sdd/reviews/<scope-id>/.current_run` を再利用（なければ日時で生成）

## 実行フロー

1. 変更差分を収集（デフォルトは `DIFF_MODE=auto`）
2. テストを実行（任意）し、結果を記録
3. `codex exec --output-schema` で `review.json` を生成
4. JSONを検証し、`.agentic-sdd/` 配下に保存

## 必須入力（環境変数）

### SoT（いずれか必須）

- `SOT`: 手入力のSoT（パス/リンク/要約など）
- `GH_ISSUE`: GitHub Issue番号またはURL（`gh issue view`で取得）
- `GH_ISSUE_BODY_FILE`: Issue本文を含むローカルファイル（テスト/オフライン用）
- `SOT_FILES`: 追加で読み込みたいローカルファイル（repo-relative、スペース区切り）

### Tests（いずれか必須）

- `TESTS` または `TEST_COMMAND`
  - `TESTS`: テスト結果サマリ（例: `not run: reason` 可）
  - `TEST_COMMAND`: 実行するテストコマンド（例: `npm test`）

## オプション（環境変数）

- `GH_REPO`: `OWNER/REPO`（Issue URL 以外を渡す場合のリポジトリ指定）
- `GH_INCLUDE_COMMENTS`: `1` の場合、Issue JSONにコメントも含める（デフォルト: `0`）
- `SOT_MAX_CHARS`: SoTまとめの最大文字数（0=制限なし）。超えた場合は末尾をカットして `[TRUNCATED]` を付与（要約はしない）

- `DIFF_MODE`: `auto` | `staged` | `worktree`（デフォルト: `auto`）
  - `auto` で staged と worktree の両方に差分がある場合は停止し、選択を求める
- `MODEL`: Codex モデル（デフォルト: `gpt-5.2-codex`）
- `REASONING_EFFORT`: `high` | `medium` | `low`（デフォルト: `high`）
- `CONSTRAINTS`: 追加制約（デフォルト: `none`）

## 出力

- `.agentic-sdd/reviews/<scope-id>/<run-id>/review.json`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/diff.patch`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/tests.txt`
- `.agentic-sdd/reviews/<scope-id>/<run-id>/sot.txt`

## SoT自動取り込みの挙動

- `GH_ISSUE` / `GH_ISSUE_BODY_FILE` が与えられた場合、Issue本文をSoTに含める
- Issue本文の `- Epic:` / `- PRD:` を解析し、参照先の `docs/epics/...` / `docs/prd/...` を読み込んでSoTに含める
  - PRD/Epicは「広め」の抜粋（先頭の `##` セクション + `## 1.`〜`## 8.` セクション）
  - `- Epic:` / `- PRD:` が存在するのに解決できない場合は停止（fail-fast）

## 判定と次アクション（続行/終了）

`review.json` の `status` を見て、次のアクションを決める。

- `Approved`: 終了（次は `/review`）
- `Approved with nits`: 原則終了（nitsはまとめて修正し、必要なら最後に1回だけ再実行）
- `Blocked`: 続行（priority 0/1 を修正して再実行）
- `Question`: 続行（質問に回答して再実行。回答できない場合は仕様/方針を確定してから進める）

## 例

```bash
SOT="docs/prd/example.md docs/epics/example.md" \
TEST_COMMAND="npm test" \
DIFF_MODE=auto \
MODEL=gpt-5.2-codex \
REASONING_EFFORT=high \
./scripts/review-cycle.sh issue-123
```

GitHub Issue から自動でSoTを構築する例:

```bash
GH_ISSUE=123 \
TESTS="not run: reason" \
DIFF_MODE=staged \
./scripts/review-cycle.sh issue-123
```

## 関連

- `.agent/commands/review.md` - 最終ゲート（DoD + `/sync-docs`）
- `.agent/schemas/review.json` - レビューJSONスキーマ（review-v2互換）
