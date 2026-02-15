# Epic: Agentic-SDD（Harness engineering観点の強化）

> PRDを参照し、Agentic-SDD 自身の「索引/契約/評価仕様/回収ループ（GC）」を最小追加する。

---

## メタ情報

- 作成日: 2026-02-14
- 作成者: @ToaruPen
- ステータス: Draft
- 参照PRD: `docs/prd/agentic-sdd-harness-engineering.md`

参考:

- 検討メモ: [`docs/memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md`](../memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md)
- 記事: https://openai.com/index/harness-engineering/

---

## 1. 概要

### 1.1 目的

PRDの目的に従い、非決定的な生成を「決定的入力（参照可能なSoT）」と「決定的評価（fail-closedのゲート）」で囲い、腐敗を定期的に回収する運用（GC）の入口を整える。

### 1.2 スコープ

**含む:**
- SoT索引（`docs/sot/`）と評価定義（`docs/evaluation/`）の最小構造
- docs lint（プレースホルダ残、相対リンク切れ等）
- scheduled GC workflow テンプレ（docs lint 実行）
- 実行計画（progress/decision log）テンプレ（任意）
- quality score テンプレ（任意）

**含まない（PRDのスコープ外を継承）:**
- オーケストレーション基盤の実装
- UI/CDP/観測スタック等のプロダクト固有能力を Agentic-SDD 本体に組み込むこと

### 1.3 PRD制約の確認

項目: 規模感
PRDの値: 小規模
Epic対応: 変更は小さく分割し、Issue粒度（50-300LOC/1-5ファイル）を維持

項目: 技術方針
PRDの値: シンプル優先
Epic対応: 追加依存は最小。まずはPython stdlib/Bashで成立させる

項目: 既存言語/FW
PRDの値: Yes
Epic対応: Bash + Python3 を継続

項目: デプロイ先
PRDの値: Yes
Epic対応: GitHub / GitHub Actions を前提にテンプレを用意

---

## 2. 必須提出物（3一覧）

### 2.1 外部サービス一覧

外部サービス-1
名称: GitHub（Issue/PR）
用途: 変更の入力（Issue）と成果物（PR）の一次置き場
必須理由: Agentic-SDD のワークフローが `gh` 前提の箇所がある
代替案: N/A

外部サービス-2
名称: GitHub Actions
用途: CI/GCテンプレ（オプトイン）
必須理由: テンプレの提供先として最も一般的
代替案: N/A（他CIはプロジェクト側で適用）

### 2.2 コンポーネント一覧

コンポーネント-1
名称: docs（SoT索引/評価定義）
責務: map-not-manual の索引と、quality gate の参照先を提供
デプロイ形態: N/A

コンポーネント-2
名称: scripts（lint/検査スクリプト）
責務: docsの腐敗を機械的に検知してfailする
デプロイ形態: N/A

コンポーネント-3
名称: GitHub Actions workflow テンプレ（オプトイン）
責務: docs lint/GC や PRコメント駆動autofix等を実行する入口（いずれも opt-in）
デプロイ形態: GitHub Actions

### 2.3 新規技術一覧

新規技術-1
名称: なし
カテゴリ: -
既存との差: -
導入理由: -

---

## 3. 技術設計

### 3.1 アーキテクチャ概要

システム境界: Agentic-SDD リポジトリ内（docs/ と scripts/ と templates/）の構造・検査・テンプレ提供に限定する。

主要データフロー-1
from: docs（PRD/Epic/索引/評価定義）
to: docs lint（ローカル/CI）
用途: 腐敗（未完了/参照切れ）をfail-closedで検出
プロトコル: ローカル実行 / GitHub Actions

主要データフロー-2
from: scheduled workflow（テンプレ）
to: docs lint
用途: 定期回収（GC）の入口
プロトコル: GitHub Actions

### 3.2 技術選定

技術選定-1
カテゴリ: ドキュメントlint実装
選択: Python3（stdlibのみ）
理由: 既存の `scripts/*.py` があり、OS差分を抑えつつ構造化したエラーメッセージを出しやすい

より簡単な代替案:
- Bash + `rg`/`grep` で最小の検査を行う（ただし、除外/表示/拡張性が弱い）

### 3.3 データモデル（概要）

N/A（ドキュメント/テンプレ中心）

### 3.4 API設計（概要）

N/A（ドキュメント/テンプレ中心）

### 3.5 プロジェクト固有指標（任意）

固有指標-1
指標名: docs lint の検出精度（偽陽性/偽陰性）
測定方法: 既存ドキュメントに対するlint結果と、意図的な違反ファイルでの再現テスト
目標値: 既存ドキュメントで false positive 0（もしくはignoreで管理）、違反は必ず検出
Before/After記録方法: CIログ、lint出力のサンプルを docs に記録

---

## 4. Issue分割案

### 4.1 Issue一覧

Issue-1
番号: 67
Issue名: SoTの地図(docs/sot)と評価定義(docs/evaluation)の最小構造を追加
概要: 索引とquality-gatesの置き場を作り、参照を固定する
推定行数: 50-150行
依存: #66

Issue-2
番号: 68
Issue名: docs/SoT lint(プレースホルダ/参照切れ)を追加
概要: Approved状態の未完了やリンク切れを機械的に検知する
推定行数: 80-200行
依存: #67

Issue-3
番号: 69
Issue名: GC(定期回収)のテンプレ(workflow)を追加
概要: scheduledでlintを回すテンプレを用意する
推定行数: 50-150行
依存: #68

Issue-4
番号: 70
Issue名: 実行計画(exec-plans)のテンプレと進捗/判断ログの置き方を追加
概要: progress/decision を repo に残す最小テンプレを定義する
推定行数: 50-150行
依存: #66

Issue-5
番号: 71
Issue名: Quality score(品質の健康診断)のテンプレを追加
概要: 品質の定点観測テンプレを追加する
推定行数: 50-150行
依存: #67

Issue-6
番号: 77
Issue名: PRレビュー返信をイベント駆動で傍受しautofix→commit/push→再待機するテンプレを追加
概要: `issue_comment` をMVPとして、deny-by-defaultのガードレール付きでautofixを起動する雛形を提供する
推定行数: 200-500行
依存: N/A

### 4.2 依存関係図

依存関係（関係を1行ずつ列挙）:
- Issue 67 depends_on Issue 66
- Issue 68 depends_on Issue 67
- Issue 69 depends_on Issue 68
- Issue 70 depends_on Issue 66
- Issue 71 depends_on Issue 67

---

## 5. プロダクション品質設計（PRD Q6に応じて記載）

### 5.1 パフォーマンス設計（PRD Q6-7: Yesの場合必須）

PRD Q6-7: No
N/A（パフォーマンス要件なし）

### 5.2 セキュリティ設計（PRD Q6-5: Yesの場合必須）

PRD Q6-5: No
N/A（個人情報/機密データなし）

### 5.3 観測性設計（PRD Q6-6: Yesの場合必須）

PRD Q6-6: No
N/A（監査ログ要件なし）

### 5.4 可用性設計（PRD Q6-8: Yesの場合必須）

PRD Q6-8: No
N/A（可用性要件なし）

---

## 6. リスクと対策

リスク-1
リスク: docs lint が厳しすぎて導入初期に運用が剥がれる
影響度: 中
対策: Phase 1 は最小の強制（プレースホルダ/リンク切れ）に限定し、追加ルールは段階導入

リスク-2
リスク: 「正本」が増えて SoT 階層が曖昧になる
影響度: 高
対策: `docs/sot/` / `docs/evaluation/` は索引/契約に限定し、要求本文の正本は PRD/Epic に残す
