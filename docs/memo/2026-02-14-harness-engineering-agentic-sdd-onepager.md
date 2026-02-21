---
title: "改修案 1枚絵: Harness engineering 観点での Agentic-SDD 強化"
date: 2026-02-14
source:
  - https://openai.com/index/harness-engineering/
---

# 改修案 1枚絵: Harness engineering 観点での Agentic-SDD 強化

狙い: 「LLMが頑張る」ではなく、決定的入力(SoT)と決定的評価(ゲート)と継続回収(GC)で品質を複利化する。

```mermaid
flowchart TB
  %% ===== Knowledge / SoT =====
  subgraph K[Repo Knowledge (SoT)
  "map-not-manual" / progressive disclosure]
    PRD[PRD: docs/prd/*.md]
    EPIC[Epic: docs/epics/*.md]
    KB[追加(提案): docs/sot/ + docs/architecture/ + docs/evaluation/\n(索引 + 契約 + ゲート定義)]
  PLANS[追加(提案): exec-plans/ (progress / decision log)\n凍結スナップショット]
  end

  %% ===== Orchestration =====
  subgraph O[Orchestration (どちらか一つ)
  ※責務分離を明示し混在しない]
    MANUAL[人間(手動):\nIssueを選び、コマンドを順に実行]
    EXT[外部ハーネス(推奨):\nstate/progress/queue/parallel を SoT にする]
  end

  %% ===== Work Execution =====
  ISSUE[GitHub Issue (実行キュー/短命SoT)
  - PRD:/Epic: の参照を持つ] --> RESOLVE[/resolve (決定的入力解決)
  PRD/Epic/diff を一意に確定\n曖昧ならSTOP]
  RESOLVE --> ASSEMBLE[/assemble-sot
  sot.txt を生成(上限/切り詰め)]

  %% ===== Gates / Loops =====
  EST[/estimation + approval
  estimate.md を凍結 + hash一致必須] --> IMPL[/impl | /tdd
  (実装 + テスト)]

  IMPL --> RC[/review-cycle (local loop)
  review.json生成→検証→修正\n1-3サイクルで収束]
RC --> REVIEW[/final-review (最終ゲート)
  DoD + /sync-docs]
  REVIEW --> PR[/create-pr
  review.json(Approved)を要求]

  %% ===== Agent-to-agent review loop (optional) =====
  PR -. optional .-> CODX[/codex-pr-review
  @codex review → 修正 → 再レビュー]

  %% ===== GC loop (proposal) =====
  subgraph GC[GC / Doc-gardening (提案)
  悪いパターンの増殖を定期回収]
    LINT[docs lint (提案)
    - Approved状態のプレースホルダ残\n- 相対リンク切れ\n- PRD/Epic参照の実在]
    BOUND[boundary lint (提案)
    - 仕様フォーマット + 言語別テンプレ\n(import-linter / Nx / ESLint / Semgrep 等)]
    QS[quality score (提案)
    ドメイン/レイヤ別の健康診断を時系列追跡]
  end

  %% Wiring
  PRD --> RESOLVE
  EPIC --> RESOLVE
  KB -. expands .-> RESOLVE
  PLANS -. evidence .-> REVIEW

  EXT -. executes .-> EST
  EXT -. executes .-> RC
  MANUAL -. executes .-> EST
  MANUAL -. executes .-> RC

  MANUAL -. scheduled .-> GC
  EXT -. scheduled .-> GC
  GC -. opens PR/Issue .-> PR

  %% Styling hints
  classDef gate fill:#fff4cc,stroke:#a07b00,stroke-width:1px;
  classDef proposal fill:#eaffea,stroke:#2b7a2b,stroke-width:1px;
  classDef orch fill:#eef4ff,stroke:#315ea8,stroke-width:1px;

  class RESOLVE,ASSEMBLE,EST,RC,REVIEW,PR gate;
  class KB,PLANS,LINT,BOUND,QS proposal;
  class MANUAL,EXT orch;
```

## 現状(根拠: 既存の決定性/ゲート)

- 入力解決の fail-fast: `.agent/commands/sync-docs.md:23-51`
- ローカル反復(1-3サイクル目安): `.agent/commands/review-cycle.md:36-46`
- 承認ゲート(estimate.md の hash 凍結): `scripts/agentic-sdd/validate-approval.py:88-91`, `scripts/agentic-sdd/validate-approval.py:226-239`
- worktree ゲート(issueブランチは linked worktree 必須): `scripts/agentic-sdd/validate-worktree.py`
- PR作成ゲート(review.json Approved必須): `scripts/agentic-sdd/create-pr.sh:163-208`
- 外部ハーネスとの責務分離(オーケストレーションSoTと混在しない): `README.md:38-49`

## 改修の要点(提案)

- map-not-manual: 追加Docsは「本文の正本」ではなく索引と契約(参照先)に限定し、PRD>Epic>実装の階層は維持
- 実行ログの一次成果物化: progress/decision を repo にスナップショットして再現性を上げる(外部Issue編集の影響を減らす)
- GCの標準化: scheduled で docs/boundary/quality を回し、結果を小さいPR/Issueとして回収するテンプレを提供
- agent-to-agent review: /codex-pr-review を「反復プロトコル」として明確に位置付け、停止条件を機械的に揃える

## 責務分割図(現実装の到達範囲)

前提: Agentic-SDD は「spec-driven workflow + quality gates」層であり、オーケストレーションSoTは外部ハーネスに寄せる(`README.md:38-49`)。

```mermaid
flowchart LR
  %% ===== Lanes =====
  subgraph H[外部ハーネス(オーケストレーションSoT)
  state/progress/queue/parallel]
    H1[タスクキュー/並列実行]
    H2[状態・進捗(単一のSoT)]
    H3[自動実行(スケジュール/常駐)
    GC/回収PRの起票]
    H4[権限/秘密情報/実行環境の管理]
  end

  subgraph A[Agentic-SDD(ポリシー + 評価仕様層)
  PRD→Epic→Issue→見積承認→実装→レビュー]
    A1[PRD/Epicテンプレ + 生成コマンド]
    A2[見積/承認ゲート(凍結hash)]
    A3[決定的入力解決(曖昧ならSTOP)]
    A4[review-cycle(ローカル反復) + review.jsonスキーマ]
    A5[sync-docs(SoT階層の整合) + DoD]
    A6[PR作成ゲート(Approved要求)]
    A7[GCテンプレ(提案)
    docs lint/boundary lint/quality score]
  end

  subgraph P[各プロジェクトrepo(プロダクト固有能力)
  アプリ/テスト/観測/境界]
    P1[テスト/ビルド/typecheck/lint]
    P2[境界lint(言語別: import-linter/Nx/ESLint/Semgrep等)]
    P3[UI検証(Playwright/CDP) ※記事の強い部分]
    P4[観測(ログ/メトリクス/トレース)
    worktree毎のephemeral環境]
  end

  %% ===== Wiring (who triggers what) =====
  H1 --> A1
  H1 --> A2
  H1 --> A4
  H3 --> A7

  A2 --> P1
  A4 --> P1
  A5 --> A1
  A7 --> P2
  A7 -. optional .-> P3
  A7 -. optional .-> P4

  %% ===== Notes =====
  classDef high fill:#eaffea,stroke:#2b7a2b,stroke-width:1px;
  classDef mid fill:#fff4cc,stroke:#a07b00,stroke-width:1px;
  classDef low fill:#ffeef0,stroke:#a83c4a,stroke-width:1px;

  %% 実現可能性(このrepo単体)の目安
  class A1,A2,A3,A4,A5,A6 high;
  class A7 mid;
  class P3,P4 low;
```

- 高(このrepoで完結しやすい): 仕様ワークフロー/決定性/ゲート/反復(= Agentic-SDDの中核)
- 中(テンプレは作れるが運用・権限に依存): GCの自動回収、quality scoreの継続更新
- 低(プロジェクト実装が本体): UI/CDP、観測スタック(ephemeral)
