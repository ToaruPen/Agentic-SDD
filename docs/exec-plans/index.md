# 実行計画（exec-plans）

このディレクトリは、実装の「進め方」「判断の根拠」「進捗ログ」を repo 内の一次成果物として残すための置き場です。

狙い:

- 外部Issueの編集（履歴の揺れ）に影響されず、レビュー/GCで追跡できるようにする
- PRD/Epic/Issue だけでは残りにくい「なぜそうしたか」を、後から再現できる形で凍結する

---

## ディレクトリ構成（推奨）

- `docs/exec-plans/active/` : 実装中
- `docs/exec-plans/completed/` : 完了済み（後から参照する）
- `docs/exec-plans/tech-debt/` : 技術的負債（改善計画/投資判断）

補足:

- Gitは空ディレクトリを追跡しないため、必要なら各ディレクトリにREADMEを置く

---

## ファイル命名（推奨）

以下のどちらかを推奨（grepしやすいものを優先）:

- `issue-<n>-<short>.md` 例: `issue-123-add-docs-lint.md`
- `YYYY-MM-DD-<short>.md` 例: `2026-02-14-docs-lint.md`

---

## 参照関係（1方向）

原則:

- exec-plans は PRD/Epic/Issue/PR を参照する（exec-plans -> PRD/Epic/Issue/PR）
- PRD/Epic を exec-plans にリンクさせることは必須にしない（循環参照を避ける）

例外（任意）:

- 外部Issue側に exec-plan へのリンクを張るのは「利便性のための付加情報」として許容する
  - ただし、repo 内の追跡は exec-plans 側を正とする（外部編集で揺れうるため）

---

## 外部Issue編集で履歴が揺れる問題への方針（何を凍結するか）

exec-plan には、少なくとも次を **コピーして凍結** する:

- Issue URL / 番号 / タイトル
- 実装開始時点の受け入れ条件（AC）/ 制約 / 変更対象ファイル（推定）
- 重要な判断（Decision log）と、その根拠（リンク/測定/テスト結果）

推奨:

- Issue本文を丸ごと貼り付けるのではなく、「後から読み直すと決定的な情報」だけを抜粋する
- ログは追記（append-only）を基本にし、過去の判断を書き換えない

---

## テンプレ

- テンプレ: [`docs/exec-plans/_template.md`](_template.md)

---

## テンプレを1回分埋める手順

初めて exec-plan を作成する場合の最小手順:

1. `_template.md` をコピーして `active/issue-<n>-<short>.md` として保存する
2. **メタ情報** を埋める（作成日・作成者・対象Issue）
3. **関連** に Issue URL を貼る（PRD/Epic は任意）
4. **凍結スナップショット** に、Issue本文から AC・制約・変更対象ファイルを抜粋してコピーする
   - 丸ごとコピーではなく「後から読み直すと決定的な情報」だけを抜粋する
5. **実行計画** は Lightweight か Heavyweight のどちらか一方だけ埋める（不要な方は削除してよい）
6. 実装中は **進捗ログ** と **判断ログ** に追記していく（append-only）
7. 完了後は `completed/` に移動し、ステータスを `Completed` に更新する

---

## 関連ドキュメント

- 判断ログの昇格先: [`docs/decisions/README.md`](../decisions/README.md)
- Decision インデックス: [`docs/decisions.md`](../decisions.md)
- exec-plans の判断ログと Decision 本文の使い分け: [`docs/decisions/README.md`](../decisions/README.md) の「exec-plans の判断ログとの関係」セクション
