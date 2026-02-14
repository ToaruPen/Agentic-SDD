# /supervise

Supervisor command for Shogun Ops. It uses GitHub Issues as the SoT, selects targets and detects conflicts (overlap in declared change targets), and updates orders/decisions and state/dashboard.

Currently, only `--once` is implemented.

## Usage

```
/supervise --once [--targets <issue>]... [--gh-repo OWNER/REPO]
```

## Script

```bash
# Example: auto-select Issues labeled parallel-ok (per config.yaml)
python3 scripts/shogun-ops.py supervise --once

# Example: explicitly specify target Issues
python3 scripts/shogun-ops.py supervise --once --gh-repo OWNER/REPO --targets 123 --targets 124
```

## Notes

- If overlap is detected, it does not emit orders; instead it updates `queue/decisions/*.yaml` and the blocked state in `state.yaml`.
- Overlap detection uses `scripts/worktree.sh check`.
