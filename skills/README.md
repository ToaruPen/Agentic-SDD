# Skills（方式設計スキル）

実装時に参照する設計パターンとチェックリスト集。

---

## 概要

Skills は、特定の実装パターンにおける設計指針とチェックリストを提供します。
言語/フレームワーク非依存で、概念ベースで記述されています。

---

## スキル一覧

- [estimation.md](./estimation.md): 見積もりスキル（Issue実装前の見積もり作成）
- [api-endpoint.md](./api-endpoint.md): API エンドポイント設計（REST API の設計・実装）
- [crud-screen.md](./crud-screen.md): CRUD 画面設計（一覧・詳細・作成・編集画面）
- [error-handling.md](./error-handling.md): エラーハンドリング（エラー分類・処理・通知）
- [testing.md](./testing.md): テスト設計（テスト戦略・種別・カバレッジ）
- [tdd-protocol.md](./tdd-protocol.md): TDD 実行規約（変更作業の進め方: Red/Green/Refactor）

---

## 使い方

### 1. 実装前に参照

```
/impl #123 を実行する前に、関連するスキルを確認:

- APIを実装する場合 → api-endpoint.md
- 画面を実装する場合 → crud-screen.md
- エラー処理を設計する場合 → error-handling.md
```

### 2. チェックリストとして使用

各スキルには実装時のチェックリストが含まれています。
実装完了時にチェックリストを確認してください。

### 3. レビュー時に参照

レビュー時にスキルのチェックリストを観点として使用できます。

---

## スキルの構成

各スキルファイルは以下の構成で記述されています：

```markdown
# スキル名

## 概要
[このスキルが扱う範囲]

## 設計原則
[基本的な考え方]

## パターン
[具体的な設計パターン]

## チェックリスト
[実装時の確認項目]

## アンチパターン
[避けるべき実装]

## 関連ファイル
[参照すべき他のファイル]
```

---

## プロジェクト固有のスキル追加

プロジェクト固有のスキルを追加する場合：

1. `skills/` ディレクトリに新しい `.md` ファイルを作成
2. 上記の構成に従って記述
3. この README に追加

例：
- `skills/authentication.md` - 認証フロー
- `skills/file-upload.md` - ファイルアップロード
- `skills/batch-processing.md` - バッチ処理

---

## 関連ファイル

- `.agent/commands/impl.md` - 実装コマンド
- `.agent/rules/dod.md` - Definition of Done
- `docs/decisions.md` - 技術的意思決定
