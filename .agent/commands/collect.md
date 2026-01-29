# /collect

Shogun Ops の checkin（`queue/checkins/**.yaml`）を取り込み、`state.yaml` と `dashboard.md` を更新します。

多重実行は単一ライターロックで防ぎます（`locks/collect.lock`）。

## Usage

```
/collect
```

## Script

```bash
python3 scripts/shogun-ops.py collect
```

