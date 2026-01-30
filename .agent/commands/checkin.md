# /checkin

Lower の進捗報告を標準化するため、append-only の checkin YAML を生成します。

生成先は Shogun Ops の集積場（`git rev-parse --git-common-dir` 配下）の `queue/checkins/<worker>/` です。

## Usage

```
/checkin <issue> <phase> <percent> <summary...>
```

## Script

```bash
# 例: worker は環境変数でも可（AGENTIC_SDD_WORKER）
python3 scripts/shogun-ops.py checkin 123 implementing 40 \
  --worker ashigaru1 \
  --tests-command "npm test" \
  --tests-result fail \
  --include-staged \
  --skill-candidate "contract-expansion-triage" \
  --skill-summary "allowed_files 逸脱時の切り分け手順" \
  --needs-approval \
  --request-file app/routes.ts \
  --blocker "upstream approval is required" \
  -- モデル/ハンドラ実装。テスト1件失敗
```

## Notes

- append-only: 既存の checkin ファイルがある場合は非ゼロ終了します。
- フラグを併用する場合は、`--` 以降を summary として扱うため安全です（例: `... --tests-result pass -- 進捗メモ`）。
