# /init

Agentic-SDDワークフローを新しいプロジェクトに適用するための初期化コマンド。

## 使用方法

```
/init [プロジェクト名]
```

## 実行フロー

### Phase 1: プロジェクト情報の収集

```
プロジェクトを初期化します。以下の質問に答えてください。

1. プロジェクト名は？
2. このプロジェクトは新規ですか、既存ですか？
3. 使用するプログラミング言語/フレームワークは？（決まっていない場合は「未定」）
4. GitHubリポジトリは既にありますか？
```

### Phase 2: ディレクトリ構造の確認

既存プロジェクトの場合、現在のディレクトリ構造を確認：

```
現在のディレクトリ構造:
[構造を表示]

Agentic-SDDのファイルを追加しますか？
- .agent/ ディレクトリ
- docs/ ディレクトリ（既存の場合はマージ）
- AGENTS.md
```

### Phase 3: ファイルの配置

以下のディレクトリとファイルを作成：


- `.agent/commands/create-prd.md`
- `.agent/commands/create-epic.md`
- `.agent/commands/create-issues.md`
- `.agent/commands/impl.md`
- `.agent/commands/review.md`
- `.agent/commands/sync-docs.md`
- `.agent/rules/docs-sync.md`
- `.agent/rules/dod.md`
- `.agent/rules/epic.md`
- `.agent/rules/issue.md`
- `.agent/agents/`（空ディレクトリ）
- `docs/prd/_template.md`
- `docs/epics/_template.md`
- `docs/decisions.md`
- `docs/glossary.md`
- `skills/estimation.md`
- `AGENTS.md`

### Phase 4: 既存ファイルとの統合

既存の `docs/` がある場合：
- 既存ファイルは保持
- `prd/`, `epics/` サブディレクトリを追加
- `_template.md` ファイルを配置

既存の `AGENTS.md` がある場合：
- バックアップを作成（`AGENTS.md.bak`）
- 新しい内容で上書き or マージを確認

### Phase 5: .gitignore の更新

`.gitignore` に以下を追加（必要に応じて）：

```
# Agentic-SDD
.agent/agents/*.local.md
```

### Phase 6: 初期化完了

```markdown
## 初期化完了

Agentic-SDDのセットアップが完了しました。

### 作成されたファイル
- .agent/commands/ (6ファイル)
- .agent/rules/ (4ファイル)
- docs/prd/_template.md
- docs/epics/_template.md
- docs/decisions.md
- docs/glossary.md
- skills/estimation.md
- AGENTS.md

### 次のステップ

1. **PRD作成**: `/create-prd [プロジェクト名]`
   - 7つの質問に答えてPRDを作成

2. **用語集の更新**: `docs/glossary.md`
   - プロジェクト固有の用語を追加

3. **技術方針の決定**: 
   - シンプル優先 / バランス / 拡張性優先

### 推奨: 初回サイクル

初めて使う場合は以下の設定を推奨:
- 技術方針: シンプル優先
- 題材: 小さすぎず、単一機能
- 例外ラベル: 使わない
```

## オプション

- `--force`: 既存ファイルを上書き（確認なし）
- `--dry-run`: 実際にはファイルを作成せずプレビュー
- `--minimal`: 最小構成のみ作成（skills/は除外）

## 既存プロジェクトへの適用

既存プロジェクトに適用する場合の注意点：

1. **既存のドキュメント**: `docs/` 内の既存ファイルは保持
2. **既存のAGENTS.md**: バックアップを作成してから更新
3. **既存のワークフロー**: 段階的に移行を推奨

### 段階的移行の例

```
Week 1: /create-prd のみ使用
Week 2: /create-epic を追加
Week 3: /create-issues を追加
Week 4: フルワークフローを適用
```

## トラブルシューティング

### Q: 既存の docs/ と競合する

A: `docs/prd/` と `docs/epics/` はサブディレクトリなので、既存ファイルとは競合しません。

### Q: AGENTS.md を既に使っている

A: `--dry-run` で内容を確認し、必要に応じて手動でマージしてください。

### Q: チームで使う場合

A: 初期化後、以下をリポジトリにコミットしてください：
- `.agent/` ディレクトリ全体
- `docs/prd/_template.md`, `docs/epics/_template.md`
- `AGENTS.md`

## 関連ファイル

- `AGENTS.md` - AIエージェント設定
- `README.md` - プロジェクト概要
- `.agent/rules/` - ルール定義

## 次のコマンド

初期化後は `/create-prd` を実行してPRDを作成する。
