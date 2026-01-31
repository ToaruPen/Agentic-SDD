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

調査依頼/調査結果（decision に紐づける）:

```bash
# 調査依頼（blocker として発行）
python3 scripts/shogun-ops.py checkin 123 blocked 0 \
  --worker ashigaru1 \
  --blocker "調査依頼: なぜビルドが落ちるか調べてください" \
  -- 調査依頼を出した

# 調査結果（decision_id を指定して応答）
python3 scripts/shogun-ops.py checkin 123 implementing 0 \
  --worker researcher1 \
  --respond-to-decision "DEC-..." \
  -- 原因はX。対策はY（詳細はIssue参照）
```

## Notes

- append-only: 既存の checkin ファイルがある場合は非ゼロ終了します。
- フラグを併用する場合は、`--` 以降を summary として扱うため安全です（例: `... --tests-result pass -- 進捗メモ`）。
