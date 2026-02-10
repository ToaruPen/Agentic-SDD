# /refactor-draft

Append a refactor candidate draft into the Shogun Ops `queue/`.

Rules:

- No GitHub writes (Middle is the single writer and creates Issues as needed).
- Append-only (duplicate timestamps for the same worker fail).

The draft title and summary are user-facing artifacts and must remain in Japanese.

## Usage

```
/refactor-draft --title "<title>" [options...] -- <summary...>
```

## Script

```bash
python3 scripts/shogun-ops.py refactor-draft \
  --title "責務の混在を分割するリファクタ" \
  --smell "責務の混在" \
  --smell "重複" \
  --risk "med" \
  --impact "local" \
  --file "path/to/file.ts" \
  --worker ashigaru1 \
  --timestamp "20260129T121507Z" \
  -- \
  観測した理由 + 影響 + 提案を1-2行で（ユーザー向け/日本語）
```

## Output

Destination (under git common dir):

```
<git-common-dir>/agentic-sdd-ops/queue/refactor-drafts/<worker>/<timestamp>.yaml
```

The YAML includes:

- `refactor.suggested_labels` (label suggestions)
- `targets.files` (estimated target files)

to make it easy for Middle to convert it into a GitHub Issue.
