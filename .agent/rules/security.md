# Security Rules

セキュリティ要件があるプロジェクト向けのルール。

適用条件: PRD Q6-5（個人情報/機密データ）で「Yes」と回答した場合

---

## Required when

<!-- grepキーワード: SECURITY_REQUIRED_WHEN -->

以下のいずれかに該当する場合、このルールを適用：

- [ ] 個人情報を扱う（氏名、メール、住所、電話番号、生年月日等）
- [ ] 認証/認可がある（ログイン、権限管理、セッション）
- [ ] 外部公開される（公開API、Webサイト、モバイルアプリ）
- [ ] 機密データを扱う（社内情報、医療データ、金融データ）
- [ ] 決済/課金がある（クレジットカード、銀行口座）
- [ ] 規制対象（GDPR、HIPAA、PCI-DSS、個人情報保護法等）

---

## Not required when

<!-- grepキーワード: SECURITY_NOT_REQUIRED_WHEN -->

以下の場合は適用不要：

- ローカル専用ツール（ネットワーク非公開）
- 公開データのみ扱う（機密性なし）
- 認証なしの静的サイト
- 内部ネットワーク限定（VPN内のみ）

---

## PRD requirements

<!-- grepキーワード: SECURITY_PRD_REQ -->

PRD Q6-5で「Yes」の場合、以下を記載：

1. 扱うデータの種類（個人情報、機密情報等）
2. 規制要件の有無（GDPR、PCI-DSS等）

詳細な対策はEpicで定義する。

---

## Epic requirements

<!-- grepキーワード: SECURITY_EPIC_REQ -->

Epicに以下のセクションを必須で含める：

<epic_section name="セキュリティ設計">

### セキュリティ設計（PRD Q6-5: Yesの場合必須）

扱うデータ:
- [データ種別]: [保護レベル]
- 例: ユーザーメールアドレス: 暗号化保存
- 例: パスワード: ハッシュ化（bcrypt, cost=12）
- 例: クレジットカード: PCI-DSS準拠、トークン化

認証/認可:
- 認証方式: [例: JWT, セッション, OAuth 2.0]
- 認可モデル: [例: RBAC, ABAC]
- セッション管理: [例: 有効期限、リフレッシュトークン]

対策チェックリスト:
- [ ] 入力検証/サニタイズ
- [ ] SQLインジェクション対策（パラメータ化クエリ）
- [ ] XSS対策（エスケープ、CSP）
- [ ] CSRF対策（トークン）
- [ ] シークレット管理（環境変数、vault）

</epic_section>

---

## DoD requirements

<!-- grepキーワード: SECURITY_DOD_REQ -->

DoDで以下が必須化（Q6-5: Yesの場合）：

- [ ] セキュリティ対策がレビューされている
- [ ] シークレットがハードコードされていない
- [ ] 入力検証が実装されている
- [ ] 認証/認可が要件通り実装されている

---

## Prohibited

<!-- grepキーワード: SECURITY_PROHIBITED -->

以下は禁止：

- ハードコードされたシークレット/パスワード/APIキー
- 平文でのパスワード保存
- 検証なしの外部入力使用
- 過剰な権限付与（最小権限の原則違反）
- 機密情報のログ出力（パスワード、トークン、カード番号等）
- HTTPでの機密データ送信（HTTPS必須）

---

## Checklist

<!-- grepキーワード: SECURITY_CHECKLIST -->

### 設計時

- [ ] 扱うデータの分類が完了している
- [ ] 認証/認可方式が決定している
- [ ] 対策リストが作成されている
- [ ] 規制要件が確認されている

### 実装時

- [ ] シークレットは環境変数/vault経由
- [ ] 入力検証が境界で実施されている
- [ ] エラーメッセージに機密情報が含まれていない
- [ ] HTTPS使用（本番環境）

### レビュー時

- [ ] OWASP Top 10に対する対策を確認
- [ ] 依存関係の脆弱性を確認（npm audit, pip-audit等）
- [ ] シークレットのコミット履歴を確認

---

## Examples

<example type="good">
- パスワードはbcrypt（cost=12）でハッシュ化
- APIキーは環境変数 `API_KEY` から読み込み
- ユーザー入力はサニタイズ後にDBクエリに使用
</example>

<example type="bad">
- `const password = "admin123";`（ハードコード）
- `db.query("SELECT * FROM users WHERE id = " + userId);`（SQLインジェクション）
- `console.log("Token: " + userToken);`（機密情報のログ出力）
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/observability.md` - Logging (secret masking)
- `skills/error-handling.md` - Error handling
- `docs/prd/_template.md` - PRD Q6-5
