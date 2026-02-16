# PRD: Agentic-SDD（Harness engineering観点の強化）

> このPRDは Agentic-SDD 自身の改修（テンプレ/ルール/ゲート）を対象とする。

---

## メタ情報

- 作成日: 2026-02-14
- 作成者: @ToaruPen
- ステータス: Draft
- バージョン: 1.0

---

## 1. 目的・背景

Agentic-SDD の価値を「実行基盤」ではなく「ポリシー + 評価仕様（quality gates）層」に寄せ、非決定的な生成を決定的な入力(SoT)と決定的な判定(ゲート)で囲う。あわせて、腐敗（ドキュメント/契約の逸脱）を定期的に回収するGCの入口を用意する。

参考:

- 検討メモ: [`docs/memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md`](../memo/2026-02-14-harness-engineering-agentic-sdd-onepager.md)
- 記事: https://openai.com/index/harness-engineering/

---

## 2. 7つの質問への回答

### Q1: 解決したい問題は？

- SoT の置き場所が一意に見つけにくく、参照が「存在しない」扱いになりやすい
- ドキュメントが腐敗しても機械的に止まらず、逸脱が増殖しやすい
- 失敗が「再試行」に寄りやすく、次回以降の確実性（能力の追加）に昇格しにくい

### Q2: 誰が使う？

- Agentic-SDD のメンテナ
- Agentic-SDD を導入するプロジェクトのメンテナ/開発者
- Agentic-SDD のコマンドを実行するAIエージェント（OpenCode/Codex/外部ハーネス）

### Q3: 何ができるようになる？

- SoT の「地図（索引）」を repo 内で辿れる
- ドキュメントの腐敗（プレースホルダ残、リンク切れ、参照契約違反）をローカル/CIで検知して止められる
- GC（定期回収）を、テンプレとしてセットアップできる
- progress / decision log を repo の一次成果物として残すための置き方を標準化できる

### Q4: 完成と言える状態は？

- 本改修の PRD/Epic が作成され、後続Issueが参照できる
- `docs/sot/README.md` と `docs/evaluation/quality-gates.md` が存在し、相互参照が成立している
- docs lint が存在し、少なくとも「Approved状態のプレースホルダ残」「相対リンク切れ」を非0で検出できる
- GC（scheduled workflow）テンプレが存在し、docs lint を実行できる

### Q5: 作らない範囲は？

- オーケストレーション基盤（キュー/ワーカー/サンドボックス/長時間実行）の実装
- 特定言語/特定ビルドシステムに強く依存する境界lintの本体実装（本PRDではテンプレ/ガイドに留める）
- UI/CDP/スクリーンショット等のUI自動検証を Agentic-SDD 本体に組み込むこと
- 既存コマンドの全面置き換え（互換性を壊す変更）

### Q6: 技術的制約は？

Q6-1: 既存言語/フレームワーク固定
選択: Yes
詳細（Yesの場合）: 既存の Bash + Python3 を前提にし、追加依存は最小にする

Q6-2: デプロイ先固定
選択: Yes
詳細（Yesの場合）: GitHub（Issue/PR）と GitHub Actions（CIテンプレ）を前提にする

Q6-3: 期限
選択: Unknown
詳細（日付の場合）: -

Q6-4: 予算上限
選択: ない
詳細（あるの場合）: -

Q6-5: 個人情報/機密データ
選択: No
詳細（Yesの場合）: -

Q6-6: 監査ログ要件
選択: No
詳細（Yesの場合）: -

Q6-7: パフォーマンス要件
選択: No
詳細（Yesの場合）: -

Q6-8: 可用性要件
選択: No
詳細（Yesの場合）: -

### Q7: 成功指標（測り方）は？

指標-1
指標: docs lint の検知能力（プレースホルダ残 + 相対リンク切れ）
目標値: 意図的に違反を作ると必ず非0で失敗し、エラーに「対象ファイル + 理由」が含まれる
測定方法: `scripts/lint-sot.py`（仮）をローカルで実行し、違反ケースで exit code と出力を確認

指標-2
指標: SoT索引の可読性
目標値: `docs/sot/README.md` から SoT の主要参照先（PRD/Epic/評価定義/意思決定）に相対リンクで辿れる（リンク切れ0）
測定方法: docs lint / link check（導入した場合）と、`docs/sot/README.md` の相対リンク一覧をレビュー

---

## 3. ユーザーストーリー

### US-1: SoTを迷わず辿りたい

```text
As a メンテナ/コントリビュータ,
I want to SoTの索引（どこに何があるか）を1ファイルで辿れるようにし,
So that 参照が散逸しても修正箇所を機械的に特定できる.
```

### US-2: 腐敗を機械で止めたい

```text
As a メンテナ,
I want to Approved状態の未完了やリンク切れをCI/ローカルで検知し,
So that ドキュメントの逸脱が増殖する前に止められる.
```

---

## 4. 機能要件

FR-1
機能名: SoT索引（map-not-manual）
説明: `docs/sot/README.md` を起点に、参照先（契約/評価定義/意思決定）へ辿れる
優先度: Must

FR-2
機能名: 評価定義の置き場
説明: `docs/evaluation/quality-gates.md` に、最低限のquality gate（何をPass/Failとするか）を列挙する
優先度: Must

FR-3
機能名: docs lint
説明: プレースホルダ残・相対リンク切れ等を検知してfailできる
優先度: Must

FR-4
機能名: GCテンプレ
説明: scheduled workflow テンプレとして、docs lint（+将来のlink check等）を定期実行できる
優先度: Should

FR-5
機能名: 実行計画（progress/decision log）テンプレ
説明: 外部Issue編集で履歴が揺れる問題に対し、repoに凍結する最小スナップショットの置き方を定義する
優先度: Could

FR-6
機能名: PRレビュー返信→autofix のスターターテンプレ
説明: PRコメント等のイベントを傍受し、明示opt-in + deny-by-default + Bot allowlist を満たす場合のみ、repo内の固定コマンドを起動して自動修正→（可能なら）commit/push→証跡コメント、という最小ループの雛形をテンプレとして提供する（オーケストレーション基盤は実装しない）
優先度: Could

---

## 5. 受け入れ条件（AC）

### 正常系

- [ ] AC-1: `docs/sot/README.md` と `docs/evaluation/quality-gates.md` が追加され、相互参照（相対リンク）が成立している
- [ ] AC-2: docs lint が追加され、プレースホルダ（例: `<!--`）を含むドキュメントを検知すると非0で終了する
- [ ] AC-3: docs lint が追加され、存在しない相対パス参照を検知すると非0で終了する

### 異常系（必須: 最低1つ）

- [ ] AC-E1: docs lint が失敗したとき、出力に「対象ファイル」「失敗理由（プレースホルダ/リンク切れ等）」「次の対応（何を直すか）」が含まれる

---

## 6. 非機能要件（該当する場合）

- セキュリティ: ドキュメント検査はネットワークアクセス不要（ローカルファイルの存在/内容のみで判定可能な範囲を優先）
- その他: 既存の SoT 階層（PRD > Epic > Implementation）を崩さない

---

## 7. 規模感と技術方針

- 規模感: 小規模
- 技術方針: シンプル優先

---

## 8. 用語集

用語-1
用語: SoT（System of Record）
定義: 意思決定や要求/計画の参照元。Agentic-SDDでは PRD > Epic > 実装（コード）が優先順位を持つ

用語-2
用語: GC（Garbage Collection / doc-gardening）
定義: 逸脱スキャン→小さな修正PR/Issueで回収、を定期的に回す運用

---

## 変更履歴

- 2026-02-14: v1.0 初版作成（@ToaruPen）
