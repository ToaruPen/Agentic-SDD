# テスト戦略 - Issue #122

作成日: 2026-02-22
対象Issue: #122 test: カバレッジゲートを全体80%・純粋関数100%へ段階引き上げ

## 1. 純粋関数の定義（実用的純粋）

本Issueでは「実用的純粋」を採用する：

- **同一入力なら同一出力**（決定性）
- **外部状態に依存しない**（ファイルシステム、環境変数、時刻等）
- **副作用を持たない**（I/O書き込み、グローバル状態変更等）

**許容される例外:**
- 内部でのみ使用するキャッシュ（外部に影響しない）
- ログ出力（戻り値に影響しない限り）

## 2. 対象ファイル分類

### 2.1 純粋関数中心（テスト優先度高）

| ファイル | 純粋関数 | I/O依存 | テスト優先度 |
|----------|----------|---------|--------------|
| `sot_refs.py` | `is_safe_repo_relative`, `normalize_reference`, `find_issue_ref` | `resolve_ref_to_repo_path` (os.path) | High |
| `assemble-sot.py` | `truncate_keep_tail`, `split_level2_sections`, `extract_wide_markdown` | `read_text`, `eprint` | High |
| `lint-sot.py` | 多数のパーサー・バリデーター | ファイル読み込み、ログ出力 | High |

### 2.2 設定・抽出系（テスト優先度中）

| ファイル | 純粋関数 | I/O依存 | テスト優先度 |
|----------|----------|---------|--------------|
| `extract-issue-files.py` | パース処理 | ファイル読み書き | Medium |
| `extract-epic-config.py` | パース処理 | ファイル読み書き | Medium |
| `generate-project-config.py` | テンプレート処理 | ファイル読み書き | Medium |

### 2.3 バリデーション系（テスト優先度中）

| ファイル | 純粋関数 | I/O依存 | テスト優先度 |
|----------|----------|---------|--------------|
| `validate-approval.py` | 検証ロジック | ファイル読み込み | Medium |
| `validate-review-json.py` | JSON検証 | ファイル読み込み | Medium |
| `validate-worktree.py` | 検証ロジック | ファイル読み込み | Medium |

### 2.4 I/O中心（テスト優先度低・モック活用）

| ファイル | 主な処理 | テスト方針 |
|----------|----------|------------|
| `resolve-sync-docs-inputs.py` | ファイルパス解決 | モックでファイルシステムを模擬 |
| `check-commit-gate.py` | Git状態確認 | モックでsubprocessを模擬 |
| `check-impl-gate.py` | Git状態確認 | モックでsubprocessを模擬 |

## 3. テスト方針

### 3.1 純粋関数（100%目標）

**方針:**
- 入力→出力の境界値テスト
- エッジケース（空文字、特殊文字、境界値）
- 例外ケース（無効入力）

**例: `is_safe_repo_relative`**
```python
def test_is_safe_repo_relative():
    assert is_safe_repo_relative("foo/bar") == True
    assert is_safe_repo_relative("") == False
    assert is_safe_repo_relative("/absolute") == False
    assert is_safe_repo_relative("../escape") == False
    assert is_safe_repo_relative("foo/../bar") == False  # .. in parts
```

### 3.2 I/O依存処理（80%目標）

**方針:**
- `monkeypatch` または `mock` でファイルシステムを模擬
- 可能な限り純粋関数に分離してテスト
- 統合テストで実際のI/Oを確認

### 3.3 Shellテストとの併存

- 既存 `scripts/tests/test-*.sh` は削除しない
- 重要なパスはpytestでもカバー
- ShellテストはE2E、pytestはユニットテストとして位置づけ

## 4. 対象/非対象

### 対象（pytest coverage計測）

- `scripts/*.py`（14ファイル）
- テストファイル: `tests/python/test_*.py`

### 非対象（coverage除外設定）

- `scripts/tests/`（shellテスト）
- 生成されたコード
- 型スタブ

## 5. 段階的閾値設定

| フェーズ | 全体閾値 | 純粋関数閾値 | 目標 |
|----------|----------|--------------|------|
| 現状 | 15% | - | ベースライン |
| Phase 2完了 | 30% | 100% | 純粋関数完全カバー |
| Phase 3完了 | 50% | 100% | 中間目標 |
| 最終 | 80% | 100% | AC達成 |

## 6. 変更履歴

- 2026-02-22: v1.0 初版作成
