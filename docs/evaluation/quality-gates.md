# Quality Gates

このドキュメントは Agentic-SDD の quality gates（何を Pass/Fail とするか）を、参照可能な形で列挙する。

目的:
- 「合否がブレない」評価を定義する
- 失敗時に次のアクションが決定できる状態にする

---

## Gate一覧（最小）

### Gate 0: worktree が必須条件を満たすこと

- Pass: Issueブランチ（`issue-<n>` を含むブランチ）では linked worktree で作業している
- Fail: worktree なしで作業している（`.git/` がディレクトリのまま等）

根拠（実装/仕様）:

- enforcement: `scripts/validate-worktree.py`
- 要件（仕様）: `.agent/commands/estimation.md`, `.agent/rules/impl-gate.md`

### Gate 1: SoT の解決が決定的であること

- Pass: PRD/Epic/差分の参照元が一意に解決できる（`docs/research/**/<YYYY-MM-DD>.md` が存在する場合は契約（必須項目/止め時）も満たしている）
- Fail: 参照が曖昧 / 参照が空 / プレースホルダが残っている / `docs/research/**/<YYYY-MM-DD>.md` の必須項目が欠落している

根拠（実装/仕様）:
- `/sync-docs`: `.agent/commands/sync-docs.md`
- 入力解決: `scripts/resolve-sync-docs-inputs.py`
- /research の契約lint: `scripts/lint-sot.py`, `.agent/commands/research.md`

### Gate 2: 変更の証跡（diff）が明確であること

- Pass: レビュー対象diffが確定できる（staged/worktree/rangeの選択が矛盾しない）
- Fail: staged と worktree の両方に差分がある等で対象が不明確

根拠（仕様）:
- `/review-cycle`: `.agent/commands/review-cycle.md`

### Gate 3: 品質チェック（tests/lint/typecheck）が実行され、証跡が残ること

- Pass: 実行したコマンドと結果が記録される
- Fail: 証跡がない

例外:
- tests を実行できない場合は `not run: <reason>` を明記し、承認を得る

根拠（仕様）:
- DoD: `.agent/rules/dod.md`
- `/review-cycle` の必須入力（TEST_COMMAND または TESTS）: `.agent/commands/review-cycle.md`

### Gate 4: ローカル反復レビュー（review.json）が schema 準拠であること

- Pass: `review.json` が schema と追加制約を満たし、status が `Approved` または `Approved with nits`
- Fail: JSON不正 / schema不一致 / status が Blocked/Question

根拠（実装/仕様）:
- schema: `.agent/schemas/review.json`
- 検証: `scripts/validate-review-json.py`
- `/review-cycle` 出力: `.agent/commands/review-cycle.md`

### Gate 5: 最終レビュー（DoD + docs sync）が通ること

- Pass: `/final-review` が Approved
- Fail: DoD未達 / docs sync不一致 / 未解決のQuestion

根拠（仕様）:
- `/final-review`: `.agent/commands/final-review.md`
- docs syncルール: `.agent/rules/docs-sync.md`

---

## Gateの扱い（fail-closed）

- 不明確な入力（参照/差分/証跡）を「推測」で補完しない
- JSONが空/不正の場合は Blocked 相当として扱い、次のアクション（修正 or 情報追加）を要求する

---

## Gateではない評価（健康診断）

合否ではなく、改善投資の意思決定やGCの回収方針に使う。

- Quality score テンプレ: [`docs/evaluation/quality-score.md`](quality-score.md)
