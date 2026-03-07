# CotoCoto Database Schema Design

**言語**: English
**最終更新**: 2026-03-07
**ステータス**: Design Documentation (実装フェーズ前設計書)

---

## 概要

このドキュメントはCotoCotoプロジェクトの将来的なデータベーススキーマ設計を定義します。
リアルタイム協調編集・無限キャンバス・マルチユーザー機能に対応した構造を設計しています。

---

## スキーマ設計方針

### 型の選択原則

| 決定 | 理由 |
|------|------|
| **Primary Key**: `binary_id` (UUID v4) | Phoenix/Elixir標準。スケーラビリティ、分散システム対応 |
| **Timestamps**: `inserted_at` / `updated_at` | Ectoの`timestamps()`マクロで自動生成。慣例に統一 |
| **cards.x, cards.y**: `float` | 64bit浮動小数点数。無限キャンバスの絶対座標に対応 |
| **cards.z**: `integer` | 32bit整数。スタック順序（レイヤー）を表現 |

### Null制約戦略

- **Essential metadata** (id, timestamps, FK): `NOT NULL` 常に
- **Business data** (title, email): `NOT NULL` 常に
- **Optional data** (description, content): `nullable`

---

## テーブル定義

### 1. users テーブル

ユーザーアカウント・認証情報を管理します。

```sql
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  hashed_password text NOT NULL,
  name text NOT NULL,
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now()
);
```

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| `id` | `uuid` | PK | ユーザーID（UUID v4） |
| `email` | `text` | NOT NULL, UNIQUE | ログイン用メール、テナント分離 |
| `hashed_password` | `text` | NOT NULL | bcryptハッシュ（Phoenix デフォルト） |
| `name` | `text` | NOT NULL | ユーザー表示名 |
| `inserted_at` | `timestamp` | NOT NULL | 作成日時 |
| `updated_at` | `timestamp` | NOT NULL | 更新日時 |

**インデックス**:
- `users_email_index` UNIQUE (email) - ログイン速度向上、重複防止

---

### 2. workspaces テーブル

各ユーザーのワークスペース（キャンバス）を管理します。1ユーザー = 複数ワークスペース。

```sql
CREATE TABLE workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now()
);
```

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| `id` | `uuid` | PK | ワークスペースID |
| `user_id` | `uuid` | NOT NULL, FK | 所有ユーザー。削除時CASCADE |
| `title` | `text` | NOT NULL | ワークスペース名（例: "Product Ideas", "Daily Fermentation"） |
| `description` | `text` | nullable | ワークスペース説明 |
| `inserted_at` | `timestamp` | NOT NULL | 作成日時 |
| `updated_at` | `timestamp` | NOT NULL | 更新日時 |

**インデックス**:
- `workspaces_user_id_index` (user_id) - ユーザーのワークスペース一覧取得高速化

**Cascade削除**: ユーザー削除時、そのワークスペース内のすべてのカードも削除

---

### 3. cards テーブル

ワークスペース内のカード（アイデア）を管理します。

```sql
CREATE TABLE cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text,
  x float NOT NULL DEFAULT 0.0,
  y float NOT NULL DEFAULT 0.0,
  z integer NOT NULL DEFAULT 0,
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now()
);
```

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| `id` | `uuid` | PK | カードID |
| `workspace_id` | `uuid` | NOT NULL, FK | 属するワークスペース。削除時CASCADE |
| `title` | `text` | NOT NULL | カードのタイトル |
| `content` | `text` | nullable | 詳細テキスト |
| `x` | `float` | NOT NULL, DEFAULT 0.0 | キャンバス上の絶対X座標 |
| `y` | `float` | NOT NULL, DEFAULT 0.0 | キャンバス上の絶対Y座標 |
| `z` | `integer` | NOT NULL, DEFAULT 0 | スタック順序（レイヤー） |
| `inserted_at` | `timestamp` | NOT NULL | 作成日時 |
| `updated_at` | `timestamp` | NOT NULL | 更新日時 |

**インデックス**:
- `cards_workspace_id_index` (workspace_id) - ワークスペース内全カード取得高速化
- `cards_workspace_id_z_index` (workspace_id, z) - Z順でのソート性能向上（複合インデックス）

**特徴**:
- **Absolute Positioning**: x, yは無限キャンバス用の絶対座標（負の値も可能）
- **Z-Index Management**: z値でスタック順序を管理。将来的にGenServerで一元管理予定
- **Cascade削除**: ワークスペース削除時、そのカードもすべて削除

---

### 4. collaborations テーブル（将来実装）

ワークスペースの共有・協調編集権限を管理します。**Phase 2実装予定**。

```sql
CREATE TABLE collaborations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'viewer',
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  UNIQUE(workspace_id, user_id)
);
```

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| `id` | `uuid` | PK | コラボレーション記録ID |
| `workspace_id` | `uuid` | NOT NULL, FK | 共有先ワークスペース |
| `user_id` | `uuid` | NOT NULL, FK | 招待されたユーザー |
| `role` | `text` | NOT NULL, DEFAULT 'viewer' | 権限レベル: `'owner'`, `'editor'`, `'viewer'` |
| `inserted_at` | `timestamp` | NOT NULL | 招待日時 |
| `updated_at` | `timestamp` | NOT NULL | 権限更新日時 |

**制約**:
- UNIQUE(workspace_id, user_id) - 1ワークスペースに同じユーザーは1回のみ招待

**インデックス**:
- `collaborations_workspace_id_index` (workspace_id) - ワークスペースの共有ユーザー一覧取得
- `collaborations_user_id_index` (user_id) - ユーザーがアクセス可能なワークスペース一覧取得

---

## 正規化分析 (3NF確認)

### 第1正規形 (1NF)
✅ **達成**: すべてのカラムが単一値（繰り返しグループなし）
- カードには複数コンテンツがない（`content` は単一テキスト）
- 権限も複数値ではなく単一ロール値

### 第2正規形 (2NF)
✅ **達成**: 部分関数従属なし（すべての非キー属性が複合キーに完全従属）
- 各テーブルは主キーのみ（複合キーなし）
- 各属性は主キーに完全従属

### 第3正規形 (3NF)
✅ **達成**: 推移的関数従属なし
- `cards.title` は workspace_id → title ではなく、card_id → title
- `workspaces.title` はユーザー情報を含まない（非キー属性が非キー属性に依存しない）

**結論**: すべてのテーブルが3NF を満たしており、適切に正規化されています。

---

## インデックス設計戦略

### インデックス一覧

| テーブル | インデックス | 型 | カラム | 用途 |
|---------|-------------|-----|--------|------|
| `users` | `users_email_index` | UNIQUE | email | ログイン検索、重複防止 |
| `workspaces` | `workspaces_user_id_index` | 通常 | user_id | ユーザーのワークスペース一覧取得 |
| `cards` | `cards_workspace_id_index` | 通常 | workspace_id | ワークスペース内全カード取得 |
| `cards` | `cards_workspace_id_z_index` | 複合 | (workspace_id, z) | Z順ソート時の高速化 |

### インデックス選択の理由

**複合インデックス** `(workspace_id, z)`:
- Query: `SELECT * FROM cards WHERE workspace_id = ? ORDER BY z ASC/DESC`
- インデックスだけでソート完結 → ディスクIO削減
- 将来のGenServer Z-indexマネージャーで頻繁に実行される予定

---

## 制約設計

### 外部キー (Foreign Key)

| FK | 参照先 | ON DELETE | 理由 |
|----|--------|-----------|------|
| `workspaces.user_id` → `users.id` | users | CASCADE | ユーザー削除時にそのワークスペース全削除 |
| `cards.workspace_id` → `workspaces.id` | workspaces | CASCADE | ワークスペース削除時にそのカード全削除 |
| `collaborations.workspace_id` → `workspaces.id` | workspaces | CASCADE | ワークスペース削除時に共有情報全削除 |
| `collaborations.user_id` → `users.id` | users | CASCADE | ユーザー削除時にそのユーザーの全コラボ情報削除 |

**ON DELETE CASCADE**: 親レコード削除時に子レコードも自動削除（孤立データなし）

### ユニーク制約

| テーブル | カラム | 理由 |
|---------|--------|------|
| `users` | email | ログインの一意性。メール重複防止 |
| `collaborations` | (workspace_id, user_id) | 同じワークスペースへの重複招待防止 |

---

## マイグレーション実装ガイドライン

将来のマイグレーション実装時は以下の原則を従う:

### ファイル構成
```
priv/repo/migrations/
├── 20260307_create_users.exs
├── 20260308_create_workspaces.exs
├── 20260309_create_cards.exs
└── 20260310_create_collaborations.exs
```

### Ectoマイグレーション例

```elixir
defmodule CotoCoto.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
  end
end
```

### Ectoスキーマ例

```elixir
defmodule CotoCoto.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :name, :string

    has_many :workspaces, CotoCoto.Workspaces.Workspace
    has_many :collaborations, CotoCoto.Workspaces.Collaboration

    timestamps(type: :utc_datetime)
  end
end
```

---

## 実装フェーズの注意事項

1. **マイグレーションの原子性**: 各マイグレーションは独立し、ロールバック可能に設計
2. **インデックスの作成方式**: `create index()` で明示的に作成（Unique制約は `unique_index()` 使用）
3. **timestamps型**: `:utc_datetime` を使用（マイクロ秒精度）
4. **テスト用シード**: `priv/repo/seeds.exs` で初期データを提供予定
5. **Cascade削除のテスト**: データベース制約動作をユニットテストで検証

---

## 将来の拡張案

### Phase 2 候補スキーマ

#### card_edges テーブル（関連性グラフ）
```
id, source_card_id, target_card_id, relationship_type, workspace_id
```
- カード間の関連性を有向グラフで表現
- アイデア間の因果関係や連想を記録

#### activity_log テーブル（監査ログ）
```
id, workspace_id, user_id, action, entity_type, entity_id, changes, timestamp
```
- ユーザーアクション履歴（作成・更新・削除）
- 多人数編集時の競合検出・解決に活用

#### workspace_settings テーブル（ワークスペース設定）
```
id, workspace_id, key, value
```
- グリッド間隔、配色テーマ、UI設定など
- KVS形式で柔軟に拡張可能

---

## 参考資料

- **Ecto Documentation**: https://hexdocs.pm/ecto/Ecto.html
- **Phoenix & Database Design**: https://hexdocs.pm/phoenix/ecto.html
- **Relational Database Design (3NF)**: Database normalization principles

---

**作成日**: 2026-03-07
**プロジェクト**: CotoCoto - Idea Fermentation Workspace
