# /refactor-draft

Append a refactor candidate draft into the Shogun Ops `queue/`.

Rules:

- No GitHub writes (Middle is the single writer and creates Issues as needed).
- Append-only (duplicate timestamps for the same worker fail).

## Usage

```
/refactor-draft --title "<title>" [options...] -- <summary...>
```

## Script

```bash
python3 scripts/shogun-ops.py refactor-draft \
  --title "Refactor: split mixed responsibilities" \
  --smell "mixed responsibilities" \
  --smell "duplication" \
  --risk "med" \
  --impact "local" \
  --file "path/to/file.ts" \
  --worker ashigaru1 \
  --timestamp "20260129T121507Z" \
  -- \
  Observed reason + impact + proposal in 1-2 lines (user-facing; Japanese in this repo)
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

