# CotoCoto 開発ワークフロー

このファイルは、CotoCotoプロジェクトの開発プロセス、チケット管理、GitHubとの連携方法を定義します。

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
feat/issue-<NUMBER>-<短い説明>
fix/issue-<NUMBER>-<短い説明>
docs/issue-<NUMBER>-<短い説明>
```

例：
```
feat/issue-1-tech-selection
fix/issue-5-card-drag-bug
docs/issue-2-schema-design
```

### 4. 進捗更新

作業中・完了時に Issue コメントで更新：

```bash
# Issue にコメント追加
gh issue comment <ISSUE_NUMBER> \
  --body "進捗: ✅ スキーマ定義完了、次は migration 生成"
```

定期的に：
- 進捗状況をコメント
- ブロッカーがあれば報告
- 完了前にチェックリストで完了条件を確認

### 5. Issue クローズ

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
