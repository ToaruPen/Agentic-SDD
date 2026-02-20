# /research

Create a research artifact under `docs/research/**` so that agents can proceed with less external context.

This command does not implement code.
User-facing interactions and artifacts remain in Japanese.

## Usage

```
/research prd [project-name]
/research epic [prd-file]
/research estimation [issue-number]
```

## Output location (required)

- PRD research:
  - `docs/research/prd/<project>/<YYYY-MM-DD>.md`
- Epic research:
  - `docs/research/epic/<prd-name>/<YYYY-MM-DD>.md`
- Estimation research:
  - `docs/research/estimation/issue-<n>/<YYYY-MM-DD>.md`

Notes:

- Output files are meant to be committed (reviewable + reusable).
- Start from the matching template:
  - `docs/research/prd/_template.md`
  - `docs/research/epic/_template.md`
  - `docs/research/estimation/_template.md`

## Required contract (all modes)

The output document must include the following (linted by `scripts/lint-sot.py`):

- Naming (required):
  - Research artifacts must be saved as date-based files: `YYYY-MM-DD.md`
  - Helper docs under `docs/research/**` must be named `README.md`
- Candidates: >= 5 (`候補-1` ..)
  - Each candidate uses a fixed format:
    - `概要:` (1 line)
    - `適用可否:` (Yes / Partial / No)
    - `仮説:` (what you currently believe)
    - `反証:` (what would falsify the hypothesis)
    - `採否理由:` (why Yes/Partial/No was chosen)
    - `根拠リンク:` (one or more URLs)
      - Must be written as bullet lines under the label, for example:
        - `- https://example.com`
      - Use raw URLs (do not use Markdown link syntax)
    - `捨て条件:`
    - `リスク/検証:`
- Stop conditions (required):
  - `タイムボックス:`
  - `打ち切り条件:`
- Novelty section (required):
  - Include the heading: `## 新規性判定（発火条件）`
  - For non-template artifacts, fill each trigger with `Yes` or `No` (do not leave `Yes / No`)

## Additional contract (epic mode)

For `docs/research/epic/**/YYYY-MM-DD.md` artifacts, include `## 外部サービス比較ゲート` and fill one of:

- `外部サービス比較ゲート: Required`
- `外部サービス比較ゲート: Skip（理由）`

When `Required`, all of the following are mandatory:

- `比較対象サービス:` with >= 3 entries in `- サービス名（ベンダー名）` format
- `代替系統カバレッジ:` with >= 3 entries (different alternative families)
- `評価軸（重み）:` with >= 3 entries in `- 評価軸（NN%）` format
- `定量比較表:` with required columns:
  - `サービス名 / ベンダー / 初期費用 / 月額費用 / レイテンシ / 可用性SLO / 運用負荷 / 適用判定`
  - >= 3 data rows
- `判定理由:` tied to the quantitative table

## High-novelty triggers (adjacent exploration required)

If any of these applies, adjacent exploration is required:

- Fewer than 2 direct precedents exist
- PRD Q6 still has any `Unknown`
- Any of PRD Q6-5..8 is `Yes` (PII / audit / performance / availability)

When adjacent exploration is required:

- Adjacent domains: >= 2 (`隣接領域-1` ..)
- Abstractions: <= 3 (`抽象化-1` ..)
- Mapping is required (`適用マッピング`)

If adjacent exploration is not required, you must still include the section and write:

`隣接領域探索: N/A（理由）`

## Flow

### Phase 1: Select target + create the output file

1. Determine the mode (`prd` / `epic` / `estimation`)
2. Create the output file under the required path pattern (date-based)
3. Copy the matching template and fill the meta fields

### Phase 2: Produce >= 5 candidates

For each candidate:

1. Fill the fixed-format fields
2. Write `仮説` and `反証` so a reviewer can verify the decision path
3. Include at least one evidence URL
4. Record a concrete discard condition + risk/validation
5. Record `採否理由` linked to the evidence

### Phase 2.5: Exploration quality prompt (required)

Use this checklist while filling each candidate:

- Hypothesis is explicit (`仮説:`)
- Falsification condition is explicit (`反証:`)
- Decision rationale is explicit (`採否理由:`)
- Evidence links are concrete enough to reproduce the judgment

### Phase 3: Adjacent exploration (conditional)

If high novelty triggers, fill the adjacent exploration section (>=2 adjacent domains, <=3 abstractions) and mapping.

### Phase 4: Downstream mapping

Summarize how the findings affect PRD/Epic/estimation:

- PRD: scope, differentiation, success metrics
- Epic: tech stack/architecture choices, alternatives + reasons
- Estimation: unknowns, risks, timeboxes, test plan adjustments

Also include an exploration log in the artifact:

- What was searched
- What was ruled out and why
- What remains unknown

### Phase 5: Self-check (required)

Run:

```bash
python3 scripts/lint-sot.py docs
```

If it fails, fix the research doc structure and/or broken links.

## Related

- `docs/research/prd/_template.md`
- `docs/research/epic/_template.md`
- `docs/research/estimation/_template.md`
- `scripts/lint-sot.py`

## Next command

- After `/research prd`: run `/create-prd`
- After `/research epic`: run `/create-epic`
- After `/research estimation`: run `/estimation`
