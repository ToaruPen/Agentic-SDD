# Runtime controls

Operational rules for reducing repeated context costs while preserving deterministic gates.

## Purpose

- Lower repeated prompt/context cost in long-running loops.
- Keep fail-fast behavior and review/test gate quality unchanged.
- Provide provider-aware defaults for OpenAI, Anthropic, and Gemini.

## Baseline policy

1. Keep static instruction blocks stable and front-loaded.
2. Keep volatile data (diff snippets, timestamps, latest findings) at the end.
3. Prefer small Context Packs (`.agent/agents/docs.md`) over full-doc ingestion.
4. Preserve deterministic gates (`/test-review`, `/review-cycle`, `/final-review`, `/create-pr`) regardless of cache hits.

## Prompt caching checklist

Do:

- Reuse an identical static prefix across repeated runs.
- Use provider cache controls when available (OpenAI prompt caching, Anthropic cache_control, Gemini context caching).
- Track cache read/write behavior in usage metadata for each provider.

Avoid:

- Injecting volatile fields into the cached prefix (timestamps, random IDs, changing comments).
- Assuming cache hit guarantees correctness; always keep gate checks.
- Relying on cache during major base-branch shifts without a forced fresh run.

## Compaction / context editing checklist

Do:

- Enable compaction only for long iterative loops where context size is the bottleneck.
- Keep compaction thresholds explicit and reviewable.
- Re-run a fresh full review context before `/final-review` when uncertainty is high.

Avoid:

- Compacting away required evidence for current findings/questions.
- Treating compaction as a substitute for deterministic SoT resolution.
- Using compaction when the current task depends on exact historical wording.

## Metrics to track (minimum)

- Per run: prompt bytes/chars and diff bytes.
- Provider usage fields for cache effectiveness (cached vs non-cached tokens where available).
- Review/test loop efficiency: number of reruns to reach `Approved`.
- Safety signal: count of gate failures after cache/compaction changes.

## Rollout / rollback policy

Rollout order:

1. docs + Context Pack optimization
2. prompt caching enablement
3. compaction/context editing enablement

Context Pack contract update procedure:

1. Update the canonical contract text in `.agent/agents/docs.md`.
2. Run `python3 scripts/bench-sdd-docs.py --only /research` to validate parser/contract integrity.
3. Run `python3 -m pytest -q tests/python/bench_sdd_docs_test.py` to verify docs/validator contract alignment.
4. If any step fails, stop and fix the contract drift before enabling runtime-control changes.

Rollback triggers:

- Increased `Blocked`/`Question` outcomes without corresponding diff changes
- Metadata mismatch spikes before `/create-pr`
- Reproducibility regressions across identical inputs

If any rollback trigger appears, disable the latest runtime control first and return to the previous stable stage.

## Related

- `.agent/commands/review-cycle.md`
- `.agent/commands/test-review.md`
- `.agent/commands/create-pr.md`
- `.agent/rules/docs-sync.md`
- `.agent/agents/docs.md`
