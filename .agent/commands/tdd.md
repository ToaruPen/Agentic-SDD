# /tdd

TDD（テスト駆動開発）で「変更」を進めるための補助コマンド。

このコマンドは、テストの設計詳細ではなく「TDDの進め方（Red → Green → Refactor）」にフォーカスする。

## 使用方法

```
/tdd [Issue番号]
```

## 実行フロー

### Phase 1: スコープ確定（SoT）

1. Issueを読み込み、ACを抽出
2. 関連するEpic/PRDを特定
3. 互換性（壊してはいけない外部I/F）を明確化
4. テスト実行コマンドを特定

不足情報があり、テスト（Red）を書けない場合は質問して止まる（仕様を創作しない）。

### Phase 2: テストTODO化

ACを「1サイクル=1テスト」を目安に分解し、TODOリストにする。

- テスト設計（種別、AAA、カバレッジ等）: `skills/testing.md`
- TDD運用（サイクル、Seam、レガシー戦術等）: `skills/tdd-protocol.md`

### Phase 3: TDDサイクル（Red → Green → Refactor）

TODOを1つ選んで、以下を繰り返す:

1. Red: 失敗するテストを書く
2. Red: テストを実行し、失敗を確認
3. Green: 最小の実装でテストを通す
4. Green: 全テストが通ることを確認
5. Refactor: Greenのまま重複/責務/命名を整理

非決定性（時刻/乱数/I/O等）がある場合は、先にSeamを作って制御可能にする（`skills/tdd-protocol.md`）。

### Phase 4: 出力

以下を短くまとめる:

- 追加/更新したテスト（何を保証するか）
- 実行したテストコマンドと結果
- 主要な設計判断（Seam、Extract/Sprout 等）

## 関連ファイル

- `skills/tdd-protocol.md` - TDD 実行規約
- `skills/testing.md` - テスト設計
- `.agent/rules/dod.md` - Definition of Done
- `.agent/commands/impl.md` - 実装フロー（テスト計画）
