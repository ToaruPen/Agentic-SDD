#!/usr/bin/env python3
"""Agentic-SDD metrics pipeline.

Record, aggregate, and report Plan B (Context Pack + runtime controls)
measurements for quantifying context-consumption reduction.

Usage:
    sdd-metrics.py record   --repo-root ROOT --command CMD --scope-id SID --run-id RID [--metadata-file META] [--mode MODE] [--status STATUS]
    sdd-metrics.py aggregate --repo-root ROOT [--scope-id SID]
    sdd-metrics.py report   --repo-root ROOT [--scope-id SID] [--scale N]
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import statistics
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

METRICS_SCHEMA_VERSION = 1
CONTEXT_PACK_HEADER = "[Context Pack v1]"
VALID_COMMANDS = ("review-cycle", "test-review", "create-pr")
VALID_MODES = ("context-pack", "full-docs", "auto")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _eprint(msg: str) -> None:
    print(f"[metrics] {msg}", file=sys.stderr)


def _detect_mode(repo_root: Path) -> str:
    """Detect mode: prefer SDD_METRICS_MODE env var, then check Context Pack presence."""
    env_mode = os.environ.get("SDD_METRICS_MODE", "").strip().lower()
    if env_mode in ("context-pack", "full-docs"):
        return env_mode
    # Heuristic fallback: check if docs.md contains the Context Pack header.
    # NOTE: In repos that ship docs.md with the header, this always returns
    # 'context-pack'.  Set SDD_METRICS_MODE=full-docs explicitly when
    # collecting baseline measurements without Context Pack.
    docs_path = repo_root / ".agent/agents/docs.md"
    if not docs_path.is_file():
        return "full-docs"
    try:
        text = docs_path.read_text(encoding="utf-8")
    except OSError:
        return "full-docs"
    return "context-pack" if CONTEXT_PACK_HEADER in text else "full-docs"


def _safe_int(value: Any) -> Optional[int]:
    """Extract an int from a JSON value, returning None on failure."""
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _read_metadata(path: Path) -> Dict[str, Any]:
    """Read a metadata JSON file, returning empty dict on failure."""
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


# ---------------------------------------------------------------------------
# record
# ---------------------------------------------------------------------------


def cmd_record(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    command: str = args.command
    scope_id: str = args.scope_id
    run_id: str = args.run_id
    metadata_file_arg: Optional[str] = args.metadata_file
    mode_arg: str = args.mode
    status_arg: Optional[str] = args.status

    if command not in VALID_COMMANDS:
        _eprint(f"unknown command: {command}")
        return 2

    # Mode detection
    mode = mode_arg if mode_arg != "auto" else _detect_mode(repo_root)

    # Read metadata (optional for commands like create-pr that have no own context)
    meta: Dict[str, Any] = {}
    error_reason: Optional[str] = None
    if metadata_file_arg:
        metadata_file = Path(metadata_file_arg)
        meta = _read_metadata(metadata_file)
        if not meta:
            error_reason = f"metadata file missing or unreadable: {metadata_file}"

    # Extract fields from metadata (review-cycle has richer data)
    prompt_bytes = _safe_int(meta.get("prompt_bytes"))
    sot_bytes = _safe_int(meta.get("sot_bytes"))
    diff_bytes = _safe_int(meta.get("diff_bytes"))
    engine_runtime_ms = _safe_int(meta.get("engine_runtime_ms"))
    head_sha = meta.get("head_sha", "")
    base_ref = meta.get("base_ref", "")
    cache_policy = meta.get("cache_policy")
    reused = meta.get("reused")
    review_engine = meta.get("review_engine")

    # Compute tokens approximation (1 token ≈ 4 chars ≈ 4 bytes for ASCII)
    total_bytes = None
    tokens_approx = None
    if prompt_bytes is not None:
        total_bytes = prompt_bytes
        tokens_approx = prompt_bytes // 4
    elif sot_bytes is not None and diff_bytes is not None:
        total_bytes = sot_bytes + diff_bytes
        tokens_approx = total_bytes // 4

    # Status: prefer explicit CLI arg, then extract from metadata 'status' field
    status = status_arg or meta.get("status", "") or ""

    payload: Dict[str, Any] = {
        "schema_version": METRICS_SCHEMA_VERSION,
        "recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "command": command,
        "scope_id": scope_id,
        "run_id": run_id,
        "mode": mode,
        "head_sha": head_sha,
        "base_ref": base_ref,
        "prompt_bytes": prompt_bytes,
        "sot_bytes": sot_bytes,
        "diff_bytes": diff_bytes,
        "total_bytes": total_bytes,
        "tokens_approx": tokens_approx,
        "engine_runtime_ms": engine_runtime_ms,
        "cache_policy": cache_policy,
        "reused": reused,
        "review_engine": review_engine,
        "status": status,
        "error_reason": error_reason,
    }

    # Write metrics file (avoid overwriting on duplicate run_id+command)
    metrics_dir = repo_root / ".agentic-sdd" / "metrics" / scope_id
    base_name = f"{run_id}-{command}"
    metrics_file = metrics_dir / f"{base_name}.json"
    seq = 1
    while metrics_file.exists():
        metrics_file = metrics_dir / f"{base_name}.{seq}.json"
        seq += 1
    try:
        metrics_dir.mkdir(parents=True, exist_ok=True)
        with open(metrics_file, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    except OSError as exc:
        _eprint(f"failed to write metrics: {exc}")
        return 1

    _eprint(f"recorded: {metrics_file}")
    return 0


# ---------------------------------------------------------------------------
# aggregate
# ---------------------------------------------------------------------------


def _load_all_metrics(
    repo_root: Path, scope_id: Optional[str] = None
) -> List[Dict[str, Any]]:
    """Load all metrics JSON files under .agentic-sdd/metrics/."""
    base = repo_root / ".agentic-sdd" / "metrics"
    if not base.is_dir():
        return []

    results: List[Dict[str, Any]] = []
    search_dirs = [base / scope_id] if scope_id else sorted(base.iterdir())
    for scope_dir in search_dirs:
        if not scope_dir.is_dir():
            continue
        for f in sorted(scope_dir.glob("*.json")):
            try:
                data = json.loads(f.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    results.append(data)
            except (OSError, json.JSONDecodeError):
                continue
    return results


def _median(values: List[float]) -> float:
    return statistics.median(values) if values else 0.0


def _mean(values: List[float]) -> float:
    return statistics.mean(values) if values else 0.0


def cmd_aggregate(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    scope_id: Optional[str] = args.scope_id

    records = _load_all_metrics(repo_root, scope_id)
    if not records:
        _eprint("no metrics data found")
        return 0

    # Group by mode
    by_mode: Dict[str, List[Dict[str, Any]]] = {}
    for r in records:
        m = r.get("mode", "unknown")
        by_mode.setdefault(m, []).append(r)

    # Header
    print(
        "mode\tcount\tavg_tokens\tmedian_tokens\tavg_prompt_bytes"
        "\tmedian_prompt_bytes\tavg_runtime_ms\tmedian_runtime_ms"
    )

    for mode in sorted(by_mode):
        items = by_mode[mode]
        count = len(items)
        tokens = [
            r["tokens_approx"] for r in items if r.get("tokens_approx") is not None
        ]
        pbytes = [r["prompt_bytes"] for r in items if r.get("prompt_bytes") is not None]
        runtimes = [
            r["engine_runtime_ms"]
            for r in items
            if r.get("engine_runtime_ms") is not None
        ]

        print(
            f"{mode}\t{count}"
            f"\t{_mean(tokens):.0f}\t{_median(tokens):.0f}"
            f"\t{_mean(pbytes):.0f}\t{_median(pbytes):.0f}"
            f"\t{_mean(runtimes):.0f}\t{_median(runtimes):.0f}"
        )

    return 0


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------


def cmd_report(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    scope_id: Optional[str] = args.scope_id
    scale: int = args.scale

    records = _load_all_metrics(repo_root, scope_id)
    if not records:
        _eprint("no metrics data found")
        return 0

    by_mode: Dict[str, List[Dict[str, Any]]] = {}
    for r in records:
        m = r.get("mode", "unknown")
        by_mode.setdefault(m, []).append(r)

    cp_records = by_mode.get("context-pack", [])
    fd_records = by_mode.get("full-docs", [])

    # Warn if either mode has no samples — comparison would be misleading
    if not cp_records or not fd_records:
        missing = []
        if not cp_records:
            missing.append("context-pack")
        if not fd_records:
            missing.append("full-docs")
        _eprint(
            f"insufficient data for comparison: no samples for {', '.join(missing)}. "
            f"Set SDD_METRICS_MODE to label runs for the missing mode(s)."
        )
        # Still print what we have, but skip reduction comparison
        print(f"=== Plan B Metrics Report: {scope_id or '(all scopes)'} ===")
        print()
        for mode_name, recs in sorted(by_mode.items()):
            vals = [
                r["tokens_approx"] for r in recs if r.get("tokens_approx") is not None
            ]
            avg = _mean(vals) if vals else 0.0
            print(f"  {mode_name}: {len(recs)} samples, avg {avg:.0f} tokens/run")
        print()
        print(
            "NOTE: Cannot compute reduction without both context-pack and full-docs samples."
        )
        return 0

    def _avg_tokens(recs: List[Dict[str, Any]]) -> float:
        vals = [r["tokens_approx"] for r in recs if r.get("tokens_approx") is not None]
        return _mean(vals)

    def _avg_bytes(recs: List[Dict[str, Any]]) -> float:
        vals = [r["prompt_bytes"] for r in recs if r.get("prompt_bytes") is not None]
        return _mean(vals)

    cp_avg_tokens = _avg_tokens(cp_records)
    fd_avg_tokens = _avg_tokens(fd_records)
    cp_avg_bytes = _avg_bytes(cp_records)
    fd_avg_bytes = _avg_bytes(fd_records)

    # Reduction calculation
    token_reduction_pct = 0.0
    if fd_avg_tokens > 0:
        token_reduction_pct = (1 - cp_avg_tokens / fd_avg_tokens) * 100

    byte_reduction_pct = 0.0
    if fd_avg_bytes > 0:
        byte_reduction_pct = (1 - cp_avg_bytes / fd_avg_bytes) * 100

    scope_label = scope_id or "(all scopes)"
    print(f"=== Plan B Metrics Report: {scope_label} ===")
    print()
    print(f"{'Metric':<30} {'full-docs':>14} {'context-pack':>14} {'reduction':>10}")
    print("-" * 70)
    print(f"{'Samples':<30} {len(fd_records):>14} {len(cp_records):>14} {'':>10}")
    print(
        f"{'Avg tokens/run':<30} {fd_avg_tokens:>14.0f} {cp_avg_tokens:>14.0f}"
        f" {token_reduction_pct:>9.1f}%"
    )
    print(
        f"{'Avg prompt bytes/run':<30} {fd_avg_bytes:>14.0f} {cp_avg_bytes:>14.0f}"
        f" {byte_reduction_pct:>9.1f}%"
    )
    print()
    print(f"--- Cumulative projection ({scale}x runs) ---")
    print(f"{'Total tokens (full-docs)':<30} {fd_avg_tokens * scale:>14.0f}")
    print(f"{'Total tokens (context-pack)':<30} {cp_avg_tokens * scale:>14.0f}")
    saved = (fd_avg_tokens - cp_avg_tokens) * scale
    print(f"{'Tokens saved':<30} {saved:>14.0f}")
    print()

    return 0


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Agentic-SDD metrics: record, aggregate, and report"
    )
    sub = parser.add_subparsers(dest="subcmd")

    # record
    p_rec = sub.add_parser("record", help="Record a metrics data point")
    p_rec.add_argument("--repo-root", required=True)
    p_rec.add_argument("--command", required=True, choices=VALID_COMMANDS)
    p_rec.add_argument("--scope-id", required=True)
    p_rec.add_argument("--run-id", required=True)
    p_rec.add_argument("--metadata-file", default=None)
    p_rec.add_argument("--mode", default="auto", choices=VALID_MODES)
    p_rec.add_argument("--status", default=None)

    # aggregate
    p_agg = sub.add_parser("aggregate", help="Aggregate metrics by mode")
    p_agg.add_argument("--repo-root", required=True)
    p_agg.add_argument("--scope-id", default=None)

    # report
    p_rep = sub.add_parser("report", help="Generate comparison report")
    p_rep.add_argument("--repo-root", required=True)
    p_rep.add_argument("--scope-id", default=None)
    p_rep.add_argument("--scale", type=int, default=10)

    args = parser.parse_args()
    if not args.subcmd:
        parser.print_help()
        return 2

    handlers = {
        "record": cmd_record,
        "aggregate": cmd_aggregate,
        "report": cmd_report,
    }
    return handlers[args.subcmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
