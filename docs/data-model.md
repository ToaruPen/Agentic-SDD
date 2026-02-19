# データモデル定義

プロジェクトのデータモデル（エンティティ、リレーション）を定義するドキュメント。

---

## 概要

- PRD/Epicで決定した要件に基づいて、スキーマを具体化する。
- 図表（Markdown表、ASCIIアート）は使用せず、テキストのみで記述する。

---

## エンティティ一覧

Entity-1
名前: [例: User]
説明: [ユーザー情報]
テーブル名: [users]

Entity-2
名前: [例: Post]
説明: [投稿情報]
テーブル名: [posts]

---

## エンティティ詳細

### Entity: [エンティティ名]

説明: [このエンティティの役割]
テーブル名: `[table_name]`

#### カラム定義

Column-1
カラム名: id
型: UUID/BIGINT
必須: Yes
デフォルト: auto
説明: 主キー

Column-2
カラム名: [column]
型: [type]
必須: [Yes/No]
デフォルト: [default]
説明: [説明]

Column-3
カラム名: created_at
型: TIMESTAMP
必須: Yes
デフォルト: now()
説明: 作成日時

Column-4
カラム名: updated_at
型: TIMESTAMP
必須: Yes
デフォルト: now()
説明: 更新日時

#### インデックス

Index-1
インデックス名: [idx_name]
カラム: [column]
種類: [UNIQUE/INDEX]
用途: [検索用途]

#### リレーション

Relation-1
関連先: [Entity]
種類: [1:N / N:1 / N:N / 1:1]
外部キー: [fk_column]
説明: [関連の説明]

---

## リレーション一覧（ER相当）

表記:
- 1:N: 1対多
- N:1: 多対1
- N:N: 多対多
- 1:1: 1対1

Relation-1
from: [User]
to: [Post]
種類: 1:N
外部キー: posts.user_id
説明: [例: User has many Posts]

---

## 制約・ルール

### 一意制約

Unique-1
エンティティ: [User]
カラム: [email]
説明: [メールアドレスは一意]

### 外部キー制約

FK-1
子テーブル: [posts]
親テーブル: [users]
ON DELETE: [CASCADE/SET NULL/RESTRICT]
ON UPDATE: [CASCADE]

### チェック制約

Check-1
テーブル: [users]
カラム: [age]
制約: [age >= 0]

---

## 列挙型（Enum）

### Enum: [EnumName]

Value-1
値: [VALUE_1]
説明: [説明]

Value-2
値: [VALUE_2]
説明: [説明]

---

## マイグレーション履歴

Migration-1
バージョン: 001
日付: YYYY-MM-DD
内容: 初期スキーマ作成

Migration-2
バージョン: 002
日付: YYYY-MM-DD
内容: [変更内容]

---

## 注意事項

### 命名規則

テーブル名
規則: スネークケース、複数形
例: `users`, `user_profiles`

カラム名
規則: スネークケース
例: `created_at`, `user_id`

インデックス名
規則: `idx_<table>_<column>`
例: `idx_users_email`

外部キー名
規則: `fk_<table>_<ref_table>`
例: `fk_posts_users`

### 共通カラム

Column
カラム名: id
型: UUID or BIGINT
説明: 主キー

Column
カラム名: created_at
型: TIMESTAMP
説明: 作成日時

Column
カラム名: updated_at
型: TIMESTAMP
説明: 更新日時

### 論理削除（使用する場合）

Column
カラム名: deleted_at
型: TIMESTAMP NULL
説明: 削除日時（NULLなら未削除）

---

## 関連ファイル

- `docs/prd/*.md`: PRD（要件）
- `docs/epics/*.md`: Epic（実装計画）
- `docs/decisions.md`: 技術的意思決定の索引（index）
- `docs/decisions/*.md`: 技術的意思決定の本文（1決定=1ファイル）
