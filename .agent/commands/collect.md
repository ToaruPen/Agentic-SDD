# /collect

Ingest Shogun Ops checkins (`queue/checkins/**.yaml`) and update `state.yaml` and `dashboard.md`.

Concurrent executions are prevented via a single-writer lock (`locks/collect.lock`).

## Usage

```
/collect
```

## Script

```bash
python3 scripts/shogun-ops.py collect
```
