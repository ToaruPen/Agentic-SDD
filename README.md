# Agentic-SDD

非エンジニアがLLM暴走を防ぎつつ、AI駆動開発を進めるためのワークフローテンプレート。

**Agentic-SDD = Agentic Spec-Driven Development**

---

## コンセプト

- コードが一意に決まるレベルで要件・仕様を決めてから実装
- AIの過剰提案を抑止し、シンプルな設計を促す
- PRD→Epic→Issues→実装→レビューの一貫したフロー

---

## ワークフロー

```
/create-prd → /create-epic → /create-issues → /impl → /review
     │            │              │              │         │
     ▼            ▼              ▼              ▼         ▼
  7問質問      3層抑止       行数ベース     Full見積    DoD確認
  +チェック    +3表必須      50〜300行     +信頼度    +sync-docs
```

---

## クイックスタート

### 1. PRD作成

```
/create-prd [プロジェクト名]
```

7つの質問に答えてPRDを作成。Q6は選択式、異常系ACが必須。

### 2. Epic作成

```
/create-epic [PRDファイル名]
```

技術設計とIssue分割案を作成。3つの一覧表（外部サービス/コンポーネント/新規技術）が必須。

### 3. Issue作成

```
/create-issues [Epicファイル名]
```

粒度規約（50〜300行）に従ってIssueを作成。

### 4. 実装

```
/impl [Issue番号]
```

Full見積もり（11セクション）を作成してから実装。

### 5. レビュー

```
/review
```

DoD確認と `/sync-docs` を実行。

---

## ディレクトリ構造

```
.agent/
├── commands/           # コマンド定義
│   ├── create-prd.md
│   ├── create-epic.md
│   ├── create-issues.md
│   ├── impl.md
│   ├── review.md
│   └── sync-docs.md
├── rules/              # ルール定義
│   ├── docs-sync.md
│   ├── dod.md
│   ├── epic.md
│   └── issue.md
└── agents/
    └── reviewer.md

docs/
├── prd/
│   └── _template.md    # PRDテンプレート
├── epics/
│   └── _template.md    # Epicテンプレート
├── decisions.md        # 意思決定記録
└── glossary.md         # 用語集

skills/                 # 方式設計スキル
└── estimation.md

AGENTS.md               # AIエージェント設定
```

---

## 主要なルール

### PRD完成条件

- 7問の質問形式（Q6は選択式）
- 完成チェックリスト（10項目）
- 禁止語辞書（曖昧な表現を排除）
- 異常系AC必須

### Epic過剰提案抑止

- 3層構造（PRD制約→AIルール→レビュー観点）
- カウント定義（外部サービス/コンポーネント/新規技術）
- 許可/禁止リスト（技術方針別）
- 必須提出物（3表）

### Issue粒度規約

- 変更行数: 50〜300行
- 変更ファイル数: 1〜5ファイル
- AC数: 2〜5個
- 例外ラベル（必須記入欄付き）

### 見積もりルール

- Full必須（11セクション）
- 信頼度（High/Med/Low）
- N/A明記ルール

### ドキュメント正本ルール

- PRD→Epic→実装の階層
- `/sync-docs` 出力強化（参照必須）

---

## 設計資料

詳細な設計は `DESIGN_V3.md` を参照。

---

## 対応AIツール

- Claude Code
- OpenCode
- Codex CLI

`.agent/` を正本とし、各ツール用設定は同期スクリプトで生成可能。

### ツール別セットアップ

#### Claude Code

`AGENTS.md`が自動認識されます。追加設定は不要です。

```bash
# プロジェクトルートで起動
claude
```

#### OpenCode

同期スクリプトを実行してコマンド/エージェント設定を配置してください。

```bash
# 1. 同期スクリプトを実行
./scripts/sync-agent-config.sh opencode

# 2. OpenCodeを起動
opencode
```

#### Codex CLI

同期スクリプトを実行してコマンド/ルール設定を配置してください。

```bash
# 1. 同期スクリプトを実行
./scripts/sync-agent-config.sh codex

# 2. Codex CLIを起動
codex
```

### 正本と同期の仕組み

```
.agent/          <- 正本（編集はここで行う）
    |
    +---> .opencode/  <- OpenCode用（自動生成、.gitignore対象）
    +---> .codex/     <- Codex CLI用（自動生成、.gitignore対象）
```

**注意**: `.agent/`内のファイルを編集した場合は、再度同期スクリプトを実行してください。

```bash
# すべてのツール用設定を同期
./scripts/sync-agent-config.sh all

# 変更内容のプレビュー（実際には変更しない）
./scripts/sync-agent-config.sh --dry-run
```

---

## 初回サイクルガイド

### 題材の選び方

- 推奨: 小さすぎず、単一機能
- 避ける: 外部サービス連携多数、認証、大規模リファクタ

### 初回ルール

| 項目 | 初回ルール |
|-----|----------|
| 見積もり | Full必須 |
| 例外ラベル | 使わない |
| 技術方針 | シンプル優先 |
| Q6のUnknown | 0を目指す |

### 成功判定

- [ ] PRDが完成チェックリストをすべて満たす
- [ ] Epicに3つの一覧表がすべてある
- [ ] Issueが粒度規約に収まる
- [ ] 見積もりがFullで作成されている
- [ ] `/sync-docs` で「差分なし」になる
- [ ] PRがマージされる

---

## ライセンス

MIT
