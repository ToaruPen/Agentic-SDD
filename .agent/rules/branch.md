# ブランチ命名ルール

Git ブランチの命名規約。

---

## 基本フォーマット

```
<type>/issue-<number>-<short-description>
```

例: `feature/issue-123-user-registration`

---

## Type

| Type | 用途 | 例 |
|------|------|---|
| `feature` | 新機能 | `feature/issue-123-user-registration` |
| `fix` | バグ修正 | `fix/issue-456-null-pointer` |
| `docs` | ドキュメント | `docs/issue-789-api-documentation` |
| `refactor` | リファクタリング | `refactor/issue-101-extract-utils` |
| `test` | テスト追加 | `test/issue-102-add-unit-tests` |
| `chore` | その他 | `chore/issue-103-update-deps` |

---

## Short Description

- 小文字のみ
- 単語はハイフン `-` で区切る
- 簡潔に（3〜5単語程度）
- 動詞から始める

### 良い例

```
feature/issue-123-add-user-profile
fix/issue-456-handle-null-response
refactor/issue-789-extract-validation
```

### 悪い例

```
feature/issue-123-AddUserProfile     # 大文字混在
feature/issue-123-add_user_profile   # アンダースコア
feature/123                          # 説明なし
user-profile                         # typeなし、issue番号なし
```

---

## 特殊ブランチ

| ブランチ | 用途 | 保護 |
|---------|------|------|
| `main` | 本番リリース | 直接push禁止 |
| `develop` | 開発統合（使用する場合） | 直接push禁止 |
| `release/*` | リリース準備 | 状況による |
| `hotfix/*` | 緊急修正 | 状況による |

---

## Issue番号がない場合

Issue番号がない場合は、日付または短いIDを使用：

```
feature/20240315-quick-fix
chore/tmp-experiment
```

**注意**: 可能な限りIssueを作成してから作業する。

---

## ブランチの寿命

| 種類 | 推奨寿命 | 備考 |
|-----|---------|------|
| feature | 1〜5日 | 長期化したら分割を検討 |
| fix | 1日以内 | 緊急度による |
| docs | 1日以内 | - |

---

## マージ後の削除

マージ完了後、ブランチは削除する：

```bash
# ローカルブランチ削除
git branch -d feature/issue-123-user-registration

# リモートブランチ削除
git push origin --delete feature/issue-123-user-registration
```

---

## 関連ファイル

- `.agent/rules/commit.md` - コミットメッセージルール
- `.agent/rules/issue.md` - Issue粒度規約
