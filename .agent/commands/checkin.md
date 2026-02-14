# /checkin

Generate an append-only checkin YAML to standardize progress reporting from Lower.

The output is written under Shogun Ops' collection area: `queue/checkins/<worker>/` under `git rev-parse --git-common-dir`.

## Usage

```
/checkin <issue> <phase> <percent> <summary...>
```

## Script

```bash
# Example: worker can also be set via env var (AGENTIC_SDD_WORKER)
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

Research request/response (linked to a decision):

```bash
# Research request (emit as a blocker)
python3 scripts/shogun-ops.py checkin 123 blocked 0 \
  --worker ashigaru1 \
  --blocker "調査依頼: なぜビルドが落ちるか調べてください" \
  -- 調査依頼を出した

# Research response (reply by specifying decision_id)
python3 scripts/shogun-ops.py checkin 123 implementing 0 \
  --worker researcher1 \
  --respond-to-decision "DEC-..." \
  -- 原因はX。対策はY（詳細はIssue参照）
```

## Notes

- Append-only: if a checkin file already exists, this command exits non-zero.
- When combining flags, everything after `--` is treated as the summary, which is safer (example: `... --tests-result pass -- 進捗メモ`).
