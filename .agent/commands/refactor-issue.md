# /refactor-issue

Create a GitHub Issue immediately from a refactor draft YAML in Shogun Ops (`queue/refactor-drafts/`).

This command is intended for Middle (single writer):

- Middle-only: centralizes GitHub writes
- On failure: exits non-zero and leaves the draft in `queue/`
- On success: moves the draft to `archive/refactor-drafts/` (removed from `queue/`)

Issue titles and bodies are user-facing artifacts and must remain in Japanese.
Exception: machine-readable keys/tokens used for automation may remain in English (e.g. `- PRD:`, `- Epic:`).

## Usage

```
/refactor-issue --draft <path/to/draft.yaml> [--gh-repo OWNER/REPO]
```

Or resolve by worker + timestamp:

```
/refactor-issue --worker <worker> --timestamp <YYYYMMDDTHHMMSSZ> [--gh-repo OWNER/REPO]
```

## Script

```bash
# Specify the draft path (preferred)
python3 scripts/shogun-ops.py refactor-issue \
  --gh-repo OWNER/REPO \
  --draft "<git-common-dir>/agentic-sdd-ops/queue/refactor-drafts/<worker>/<timestamp>.yaml"

# Specify worker + timestamp
python3 scripts/shogun-ops.py refactor-issue \
  --gh-repo OWNER/REPO \
  --worker ashigaru1 \
  --timestamp "20260129T121507Z"
```

## Labels

- The command applies `refactor.suggested_labels` from the draft YAML to the created Issue.
- Missing labels are created/updated via `gh label create --force` to ensure the Issue can be created deterministically.
