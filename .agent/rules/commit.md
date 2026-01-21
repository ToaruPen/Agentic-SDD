# コミットメッセージルール

Conventional Commits に基づくコミットメッセージの規約。

---

## 基本フォーマット

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

---

## Type（必須）

| Type | 説明 | 絵文字（任意） |
|------|------|--------------|
| `feat` | 新機能 | ✨ |
| `fix` | バグ修正 | 🐛 |
| `docs` | ドキュメントのみ | 📝 |
| `style` | コードの意味に影響しない変更（空白、フォーマット等） | 💄 |
| `refactor` | バグ修正でも機能追加でもないコード変更 | ♻️ |
| `perf` | パフォーマンス改善 | ⚡ |
| `test` | テストの追加・修正 | ✅ |
| `build` | ビルドシステムや外部依存に関する変更 | 📦 |
| `ci` | CI設定の変更 | 👷 |
| `chore` | その他の変更（ソースやテストの変更なし） | 🔧 |
| `revert` | 以前のコミットの取り消し | ⏪ |

---

## Scope（任意）

変更の影響範囲を示す。プロジェクトに応じて定義。

```
feat(api): add user registration endpoint
fix(ui): correct button alignment
docs(readme): update installation instructions
```

---

## Description（必須）

- 命令形で記述（例: "add" not "added"）
- 小文字で開始
- 末尾にピリオドを付けない
- 50文字以内を目安

### 良い例

```
feat(auth): add password reset functionality
fix(api): handle null response from external service
refactor(utils): extract validation logic to separate module
```

### 悪い例

```
feat(auth): Added password reset functionality.  # 過去形、ピリオド
fix: bug fix  # 具体性がない
Update code  # type がない
```

---

## Body（任意）

変更の理由や詳細を説明する場合に使用。

```
feat(auth): add password reset functionality

Users can now reset their password via email.
The reset link expires after 24 hours.

Closes #123
```

---

## Footer（任意）

### Breaking Changes

```
feat(api)!: change response format for user endpoint

BREAKING CHANGE: The user endpoint now returns an array instead of an object.
```

### Issue参照

```
fix(cart): correct total calculation

Fixes #456
Closes #789
```

---

## 絵文字の使用（任意）

絵文字を使用する場合は type の前に配置：

```
✨ feat(auth): add OAuth2 support
🐛 fix(api): handle timeout errors
📝 docs(readme): add API documentation
```

**注意**: チームで統一すること。混在は避ける。

---

## 例

### 機能追加

```
feat(user): add profile picture upload

- Support JPEG and PNG formats
- Max file size: 5MB
- Auto-resize to 200x200

Closes #234
```

### バグ修正

```
fix(payment): correct tax calculation for international orders

The tax rate was incorrectly applied to shipping costs.
Now only product prices are taxed.

Fixes #567
```

### リファクタリング

```
refactor(api): extract authentication middleware

- Move auth logic from routes to middleware
- Add unit tests for middleware
- No functional changes
```

### ドキュメント

```
docs(contributing): add commit message guidelines
```

---

## コミット粒度

### 原則

- 1コミット = 1つの論理的な変更
- 動作する状態でコミット
- レビューしやすいサイズに保つ

### 分割の目安

| 分割すべき | 1コミットでOK |
|-----------|--------------|
| 機能追加 + バグ修正 | 関連する機能追加 + テスト |
| リファクタ + 新機能 | 小さなリファクタのみ |
| 複数の独立した修正 | 1つの問題に対する修正 |

---

## 関連ファイル

- `.agent/rules/branch.md` - ブランチ命名ルール
- `.agent/rules/datetime.md` - 日時フォーマットルール
