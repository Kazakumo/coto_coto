# CotoCoto 開発ワークフロー

**このドキュメントについて**: CotoCotoプロジェクトの開発プロセス、チケット管理、GitHubとの連携方法の実行手順です。

**役割**: 実装者向けの実行書
**言語**: 日本語

**読み方**:
- GitHub Issue の作成方法を知りたい → 1. Issue 作成フェーズ
- ブランチを作成・PR を作成するまでの流れを知りたい → 3. Issue 開発フェーズ ～ 5. Issue クローズ
- コーディング規則を知りたい → CLAUDE.md / AGENTS.md を参照
- テスト戦略・エラーハンドリング設計を知りたい → ARCHITECTURE_DECISIONS.md を参照

---

## 原則

**GitHub Issue が単一の真実の源（SSOT）です。**

- すべての作業項目は GitHub Issue として存在する必要があります
- Claude Code の内部タスク（TaskCreate/TaskList）も GitHub Issue と同期します
- Issue は常に最新の状態に保たれます
- ブランチ、PR、コミットはすべて Issue を参照します

## ワークフロー

### 1. Issue 作成フェーズ

新しい機能・修正・検討が必要な場合：

```bash
gh issue create \
  --title "機能名 または チケット名" \
  --body "詳細説明" \
  --label "bug|feature|investigation|technical-debt"
```

**重要**: Issue ラベルの使い分け
- `feature`: 新機能
- `bug`: バグ修正
- `investigation`: 技術検討（デザインレビュー期間）
- `technical-debt`: リファクタリング、CI/CD 等の基盤整備
- `docs`: ドキュメント作成

### 2. Issue と Claude Code タスクの同期

新しい Issue が作成されたら：

```bash
# Issue 一覧を確認
gh issue list

# 特定 Issue の詳細を確認
gh issue view <ISSUE_NUMBER>
```

Claude Code の TaskCreate でタスクを作成する際：
- Issue 番号を description に含める（例：`GitHub Issue #5`）
- Issue タイトルと同一の subject にする

### 3. Issue 開発フェーズ

Issue 作業開始時：

```bash
# Issue を自分にアサイン
gh issue edit <ISSUE_NUMBER> --add-assignee @me

# Issue を "In Progress" に移動（Projects で管理している場合）
gh issue edit <ISSUE_NUMBER> --state open
```

**ブランチ名の規則**:
```
feat/issue-<NUMBER>
fix/issue-<NUMBER>
docs/issue-<NUMBER>
```

例：
```
feat/issue-1
fix/issue-5
docs/issue-2
```

**注**: ブランチ名に詳細説明は含めません。詳細は Issue タイトル・説明で管理します。

### 4. 進捗更新・決定ログ

作業中・完了時に Issue コメントで更新：

```bash
# Issue にコメント追加
gh issue comment <ISSUE_NUMBER> \
  --body "進捗: ✅ スキーマ定義完了、次は migration 生成"
```

#### 4.1 進捗コメント（必須）

定期的に以下を報告：
- 進捗状況（何が完了したか）
- ブロッカー（遭遇した問題、待機事項）
- 次のステップ

例：
```markdown
進捗: ✅ A 機能の実装完了
- [ ] 単体テスト (80%)
- [ ] 統合テスト (0%)

ブロッカー: B API のレスポンス仕様が未定
次: 仕様確認後、B API 統合テスト開始
```

#### 4.2 複数案の検討・意思決定ログ（必須）

複数の実装案・設計案が出た場合、必ず **メリット・デメリット整理** と **意思決定理由** を Issue コメントに記録：

```bash
gh issue comment <ISSUE_NUMBER> \
  --body "
## 検討内容: 認証方式の選定

### 候補案

#### 案A: Session ベース認証
- メリット: シンプル、CSRF 対策が標準
- デメリット: スケーラビリティ課題（サーバー状態保持）、マルチデバイス対応が弱い

#### 案B: JWT ベース認証
- メリット: ステートレス、マルチデバイス対応、API 拡張性
- デメリット: トークン無効化が複雑、署名検証コスト

#### 案C: OAuth 2.0 + OpenID Connect
- メリット: セキュリティベストプラクティス、ソーシャル連携可能
- デメリット: 実装複雑度が高い、初期開発コスト大

### 決定: **案B (JWT ベース認証)**

**決定基準**:
1. スケーラビリティ: 将来のマルチユーザー拡張を想定し、ステートレス設計を優先
2. 開発速度: Session ほどシンプルではないが、OAuth ほど複雑でなく、初期段階に適切
3. 拡張性: REST API 拡張時に JWT が必須であり、後続フェーズを見越した決定

**参照**: ARCHITECTURE_DECISIONS.md セクション X で詳細設計を記録
"

#### 4.3 試行錯誤・プロトタイピングの記録（推奨）

実装中に試行錯誤やプロトタイピングを行う場合、学んだことを記録：

```bash
gh issue comment <ISSUE_NUMBER> \
  --body "
### 試行錯誤ログ

❌ **試み 1**: LiveComponent で状態管理を試みた
- 結果: パフォーマンス低下（WebSocket 遅延）
- 理由: 多数のコンポーネント再レンダリングが過剰
- 学習: CotoCoto では LiveComponent は避けるべき

✅ **試み 2**: Phoenix.PubSub + LiveView ストリーム
- 結果: 60fps 達成、レスポンス良好
- コード例: lib/coto_coto_web/live/canvas_live.ex:45-60
- 結論: この方式を採択

**参照**: AGENTS.md の LiveView パターンセクション
"

Issue の作業が完了したら：

```bash
# PR をマージ後、Issue をクローズ
gh issue close <ISSUE_NUMBER>

# または コメント経由
gh issue comment <ISSUE_NUMBER> --body "完了しました。Closes #<ISSUE_NUMBER>"
```

PR マージ時のコミットメッセージに以下を含める：
```
feat(issue-<NUMBER>): 機能説明

詳細説明...

Closes #<ISSUE_NUMBER>
```

## 決定ログのベストプラクティス

### 目的

GitHub Issue への決定ログ記録により：
1. **追跡可能性**: なぜこの設計・実装にしたのかが明確
2. **再利用性**: 同じ検討が再度必要な場合、過去の議論から学べる
3. **チームアライメント**: 非同期コラボレーション時に意思決定根拠が明確
4. **監査**: プロジェクトの成長過程が GitHub に永続記録される

### 記録対象

以下のような場合、必ず Issue コメントで決定ログを記録：

| 場面 | 記録内容 | 例 |
|------|--------|-----|
| **複数案の検討** | 各案のメリット・デメリット、決定基準、選択理由 | 認証方式、キャッシング戦略、DB設計 |
| **技術選定** | ライブラリ・フレームワークの比較検討 | Phoenix vs Rails、Ecto vs SQL Alchemy |
| **設計決定** | アーキテクチャ・データモデルの選択 | リアルタイム同期方式、Z-index管理 |
| **試行錯誤** | 実装中に試してダメだったこと、学んだこと | LiveComponent をやめた理由、パフォーマンス改善 |
| **ブロッカー解決** | 問題の原因究明、採った対策、その結果 | なぜデータベース接続が失敗したか |

### 記録形式

**標準テンプレート**（Markdown）:

```markdown
## [検討内容 / 試行ログ / 決定]: タイトル

### 背景
なぜこの検討が必要だったのか、どの Issue #XX の一部か

### 検討対象（複数案がある場合）

#### 案 1: [方式A]
- メリット: ...
- デメリット: ...
- 実装難度: [LOW/MEDIUM/HIGH]
- 参考リンク: ...

#### 案 2: [方式B]
- メリット: ...
- デメリット: ...
- 実装難度: [LOW/MEDIUM/HIGH]
- 参考リンク: ...

### 決定（複数案から選択した場合）
**採択案**: [案X]

**決定基準** （優先度順）:
1. [基準A]: なぜ重要か
2. [基準B]: なぜ重要か
3. [基準C]: なぜ重要か

**決定理由**: 簡潔にまとめた説明

### 実装方針 / コード例
- ファイル: `lib/...`
- 参照セクション: AGENTS.md の XX、ARCHITECTURE_DECISIONS.md の YY

### 参考資料・関連 Issue
- #XX (関連タスク)
- [外部リンク](https://...)
```

### 記録ツール

```bash
# Issue コメントを追記（最も推奨）
gh issue comment <ISSUE_NUMBER> --body "決定ログコンテンツ"

# エディタで作成（複雑な場合）
gh issue comment <ISSUE_NUMBER> --body-file decision.md
```

### 記録タイミング

- ✅ **即座に記録**: 決定直後、ブレを避けるため
- ✅ **実装中の気づき**: 試行錯誤の最中に「このアプローチはダメ」という学習が出たとき
- ✅ **完了時サマリー**: Issue クローズ前に最終的な決定内容を記録

### 禁止事項

❌ **記録せず実装進行**: 後から「なぜこうしたのか」が追跡不可能
❌ **決定をコミットメッセージに隠す**: GitHub Issue が SSOT なので Issue コメントが必須
❌ **口頭決定**: チャット履歴は消える、Issue は永続記録

---

## Issue テンプレート（参考）

### Feature Issue
```markdown
## 説明
この機能は...を実現します。

## 受け入れ条件
- [ ] テスト完了
- [ ] ドキュメント更新
- [ ] コードレビュー完了

## 実装ガイドライン
- CLAUDE.md の xx セクションを参照
- ...

## 関連 Issue
- #xx
- #yy
```

### Investigation Issue
```markdown
## 検討項目
- 認証方式の選定
- リアルタイム機能の設計

## 決定基準
- パフォーマンス
- 保守性
- チームスキルセット

## 次のステップ
- [ ] 各案のメリット・デメリット整理
- [ ] 決定・ドキュメント化
```

## GitHub CLI コマンド参考

```bash
# Issue 一覧（フィルタ可能）
gh issue list --label feature --state open

# Issue の詳細確認
gh issue view 5 --web  # ブラウザで開く
gh issue view 5        # CLI で表示

# PR 一覧
gh pr list

# PR のマージ（必ず Issue 番号を参照）
gh pr merge 12 --squash  # コミット前に Issue 番号を含めることが必須

# ブランチから PR 作成（Issue リンク自動化）
gh pr create --title "feat(issue-5): Card drag" --body "Closes #5"
```

## CI/CD と自動化

GitHub Actions ワークフローは以下で自動実行：
- PR 作成時：フォーマット、テスト実行
- PR マージ時：本番デプロイ（予定）
- Issue ラベル変更時：Project ボード自動更新（予定）

詳細は `.github/workflows/` を参照。

## Issue 駆動開発のメリット

1. **追跡可能性**: 全作業が Issue に記録される
2. **非同期コラボレーション**: 詳細が Issue に残る
3. **自動化**: Issue → PR → Merge の流れで自動化可能
4. **歴史**: GitHub で全決定過程が記録される

## トラブルシューティング

**Issue と PR がリンクされない場合**:
- PR マージ時に `Closes #<NUMBER>` を含める
- または PR 詳細ページで手動でリンク

**Issue 番号を忘れた場合**:
- `gh issue list` で確認
- ブランチ名から Issue 番号を確認

**進捗更新を忘れた場合**:
- Issue コメントで遡及的に追加可能
- CI ログも参考になる
