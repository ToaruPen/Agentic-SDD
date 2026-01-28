# /generate-project-config

Epic情報からプロジェクト固有のスキル/ルールを生成する。

## Usage

```
/generate-project-config [epic-file]
```

## Overview

Epicで決まった仕様（技術選定、Q6要件）に基づいて、プロジェクト固有のスキル/ルールを生成する。

生成されるファイル:
- `config.json` - プロジェクト設定（常に生成）
- `skills/tech-stack.md` - 技術スタックガイド（技術選定がある場合）
- `rules/security.md` - セキュリティルール（Q6-5 = Yes の場合）
- `rules/performance.md` - パフォーマンスルール（Q6-7 = Yes の場合）
- `rules/api-conventions.md` - API規約（API設計がある場合）

## Flow

### Phase 1: Epicファイルの読み込み

1. 指定されたEpicファイルを読み込む
2. ファイルが存在しない場合はエラー

### Phase 2: 情報抽出

`scripts/extract-epic-config.py` を使用して以下を抽出:

1. 技術選定情報（セクション3.2）
   - 言語、フレームワーク、データベース、インフラ
2. Q6要件（セクション5）
   - Q6-5: セキュリティ要件
   - Q6-6: 観測性要件
   - Q6-7: パフォーマンス要件
   - Q6-8: 可用性要件
3. API設計情報（セクション3.4）
   - エンドポイント一覧

### Phase 3: テンプレート選択

抽出した情報に基づいて、該当するテンプレートを選択:

| 条件 | 生成ファイル |
|------|-------------|
| 技術選定がある | `skills/tech-stack.md` |
| Q6-5 = Yes | `rules/security.md` |
| Q6-7 = Yes | `rules/performance.md` |
| API設計がある | `rules/api-conventions.md` |

### Phase 4: 変数置換とファイル生成

`scripts/generate-project-config.py` を使用:

1. テンプレートファイルを読み込み
2. Jinja2形式で変数置換
3. `.agentic-sdd/project/` にファイル出力

### Phase 5: 生成内容の確認

1. 生成されたファイル一覧を表示
2. 各ファイルの概要を表示
3. ユーザーに確認を求める

## Output

```
.agentic-sdd/project/
├── config.json
├── skills/
│   └── tech-stack.md
└── rules/
    ├── security.md
    ├── performance.md
    └── api-conventions.md
```

## Example

```bash
# Epicファイルから直接生成
python scripts/generate-project-config.py docs/epics/my-project-epic.md

# 抽出と生成を分けて実行
python scripts/extract-epic-config.py docs/epics/my-project-epic.md -o /tmp/config.json
python scripts/generate-project-config.py /tmp/config.json

# ドライラン（生成予定ファイルの確認）
python scripts/generate-project-config.py docs/epics/my-project-epic.md --dry-run
```

## Notes

- 生成されるファイルはテンプレートベースのため、プロジェクト固有の詳細は手動で追記が必要
- 汎用ルール（`.agent/rules/`）は別途存在し、生成されるルールはプロジェクト固有の補足
- 既存ファイルがある場合は上書きされるため注意

## Related

- `.agent/commands/create-epic.md` - Epic作成コマンド
- `.agent/rules/security.md` - 汎用セキュリティルール
- `.agent/rules/performance.md` - 汎用パフォーマンスルール
- `templates/project-config/` - テンプレートファイル

## Next command

生成完了後、必要に応じて生成されたファイルを確認・編集し、`/create-issues` を実行してIssue分割に進む。
