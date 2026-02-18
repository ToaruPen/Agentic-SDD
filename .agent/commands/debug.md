# /debug

Create a structured debugging/investigation note for an existing Issue (as a comment), or as a new Investigation Issue.

User-facing output and artifacts must remain in Japanese.

## Usage

```
/debug <issue-number>
```

Notes:

- This command does not implement fixes. It creates evidence and a next-action plan.
- Output destination must be confirmed with the user.
- Output option: comment on the existing Issue.
- Output option: create a new Investigation Issue.

## Flow

### Phase 0: Identify the target (fail-fast)

1. Confirm the target Issue number and title.
2. Confirm output destination (comment vs new Issue).

### Phase 1: Collect evidence (OBSERVE)

Required:

- Expected behavior vs actual behavior
- Reproduction steps (minimum)
- Environment/context (OS/runtime/version/config as applicable)
- Logs/errors (copy the relevant excerpt)

If performance/reliability is involved, also include:

- SLI/metric name(s) and how measured (command/tool/dataset)
- Baseline (before) and current (after), including sample size and percentile when relevant (e.g. p50/p95)
- Load/traffic conditions and time window

### Phase 2: Hypotheses + verification plan (HYPOTHESIZE/TEST)

1. List up to 3 hypotheses.
2. For each, write a minimal verification step and what result would confirm/refute it.
3. Execute one verification at a time, record results.

### Phase 3: Publish the note (Japanese)

Option A: Comment on the existing Issue:

```bash
gh issue comment <issue-number> --body-file <path>
```

Option B: Create a new Investigation Issue:

```bash
gh issue create --title "<title>" --body-file <path>
```

Guidelines:

- Title/body must be Japanese.
- Machine-readable keys/tokens used for automation may remain in English (e.g. `- PRD:`, `- Epic:`).
- If you reference PRD/Epic, keep the same `- PRD:` / `- Epic:` format as normal Issues to enable SoT ingestion.

Template (comment or Issue body; Japanese):

```markdown
## 概要

[何が起きているか / 何を調査するかを1-2文で]

## 期待値と実際

- 期待: [期待]
- 実際: [実際]

## 再現手順（最小）

1. [...]
2. [...]

## 環境/条件

- OS:
- Runtime/Version:
- 設定/フラグ:
- データ条件:

## 証跡（ログ/スタックトレース/スクリーンショット等）

```text
[抜粋]
```

## パフォーマンス/信頼性（該当する場合）

- 指標（SLI/メトリクス名）:
- 計測方法（コマンド/ツール/データ）:
- ベースライン（Before）:
- 現状（After）:
- サンプル数/時間窓:
- 負荷条件:

## 仮説（最大3つ）

1. 仮説: [...]
   - 検証: [...]
   - 期待される結果: [...]
   - 実結果: [...]
2. 仮説: [...]
3. 仮説: [...]

## 結論（現時点）

- 原因: [確定/未確定]
- 影響範囲: [...]

## 次アクション

- [ ] [やること1]
- [ ] [やること2]
```

## Related

- `skills/debugging.md` - debugging principles and checklists
- `skills/data-driven.md` - metrics-driven investigations
