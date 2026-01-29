# /supervise

Shogun Ops の監督コマンドです。GitHub Issues を SoT として参照し、配賦対象の選別と衝突検知（declared change targets の overlap）を行い、orders/decisions と state/dashboard を更新します。

現状は `--once` のみ実装しています。

## Usage

```
/supervise --once [--targets <issue>]... [--gh-repo OWNER/REPO]
```

## Script

```bash
# 例: parallel-ok ラベルの Issue を自動選別（config.yaml に従う）
python3 scripts/shogun-ops.py supervise --once

# 例: 対象Issueを明示
python3 scripts/shogun-ops.py supervise --once --gh-repo OWNER/REPO --targets 123 --targets 124
```

## Notes

- overlap が検知された場合は orders を出さず、`queue/decisions/*.yaml` と `state.yaml` の blocked を更新します。
- overlap 検知には `scripts/worktree.sh check` を使用します。

