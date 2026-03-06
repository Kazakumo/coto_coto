# アーキテクチャ決定記録

Issue #2: 技術選定・アーキテクチャ設計の検討

## 1. 複数人同時編集の実装方式

### 決定: Phoenix.PubSub（Phoenix.Channel ではなく）

**理由**:
- **Phoenix.PubSub** は組み込み、依存性ゼロ
- LiveView で十分なリアルタイム機能を提供
- Canvas 用途では Channel の複雑性は不要
- スケーリング: Redisアダプター（後から追加可能）で水平スケーリング対応

**実装戦略**:
```elixir
# lib/coto_coto_web/live/canvas_live.ex
defmodule CotoCotoWeb.CanvasLive do
  def handle_event("move_card", %{"card_id" => id, "x" => x, "y" => y}, socket) do
    card = update_card_position(id, x, y)

    # ブロードキャスト全接続クライアントに送信
    Phoenix.PubSub.broadcast(
      CotoCoto.PubSub,
      "canvas:#{socket.assigns.canvas_id}",
      {:card_moved, card}
    )

    {:noreply, socket}
  end

  def handle_info({:card_moved, card}, socket) do
    {:noreply, stream_insert(socket, :cards, card)}
  end
end
```

**スケーリング計画**:
- Phase 1: PubSub（デフォルト Erlang Distribution）
- Phase 2: Redis アダプター（複数ノード対応）

---

## 2. Z-Index（重ね順）管理戦略

### 決定: GenServer（メモリ状態） + Database（永続化）

**2段階アーキテクチャ**:

#### Layer 1: GenServer（メモリ）
```elixir
# lib/coto_coto/canvas_state.ex
defmodule CotoCoto.CanvasState do
  use GenServer

  # 状態: %{canvas_id => [card_ids_in_order]}

  def bring_to_front(canvas_id, card_id) do
    GenServer.call(__MODULE__, {:bring_to_front, canvas_id, card_id})
  end
end
```

**役割**:
- 高速な z-index 計算（DB アクセスなし）
- 最新のカード順序を保持
- クライアント側の楽観的更新対応

#### Layer 2: Database（永続化）
```sql
-- priv/repo/migrations/xxx_create_z_indices.exs
CREATE TABLE z_indices (
  id UUID PRIMARY KEY,
  canvas_id UUID REFERENCES workspaces(id),
  card_id UUID REFERENCES cards(id),
  z_order INTEGER NOT NULL,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX ON z_indices(canvas_id, z_order);
```

**役割**:
- 永続化（アプリ再起動時の復帰）
- 監査ログ（z-index 履歴）
- マルチノード環境での同期

**同期戦略**:
- GenServer 更新 → PubSub ブロードキャスト → Database 書き込み（非同期）
- Database が source of truth
- GenServer が最新キャッシュ

---

## 3. ベクトル検索・セレンディピティ・エンジン

### 決定: Nx.Serving + bumblebee（Elixir ネイティブ）

**なぜ Nx か**:

| 選択肢 | 採用 | 理由 |
|--------|------|-----|
| Nx + bumblebee | ✓ | Elixir ネイティブ、外部 API 不要、オフラインで動作 |
| Flox | ✗ | Rust 依存性、プロダクション環境での複雑性 |
| OpenAI API | ✗ | 外部依存、実行時コスト増加、レイテンシー |

**実装計画**:

### Phase 1: 埋め込み（Embedding）の生成
```elixir
# lib/coto_coto/embeddings.ex
defmodule CotoCoto.Embeddings do
  def get_or_create_embedding(card_id, content) do
    case Repo.get_by(CardEmbedding, card_id: card_id) do
      nil ->
        # Nx.Serving で埋め込み生成
        embedding = generate_embedding(content)
        Repo.insert!(%CardEmbedding{
          card_id: card_id,
          embedding: embedding
        })
      existing ->
        existing
    end
  end

  defp generate_embedding(text) do
    # bumblebee で Sentence-BERT モデルを実行
    {:ok, model} = Bumblebee.load_model(:sentence_transformers)
    Nx.Serving.run(model, text)
  end
end
```

### Phase 2: 類似度検索
```elixir
# lib/coto_coto/serendipity.ex
defmodule CotoCoto.Serendipity do
  def find_similar_cards(card_id, top_k \\ 5) do
    card = Repo.get!(Card, card_id) |> Repo.preload(:embedding)

    # PostgreSQL pgvector 拡張
    from(e in CardEmbedding,
      select: e.card_id,
      order_by: e.embedding <-> ^card.embedding.embedding,
      limit: ^top_k
    )
    |> Repo.all()
  end
end
```

### Database スキーマ:
```sql
-- pgvector 拡張を有効化
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE card_embeddings (
  id UUID PRIMARY KEY,
  card_id UUID UNIQUE REFERENCES cards(id),
  embedding vector(384),  -- Sentence-BERT の次元数
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX ON card_embeddings USING ivfflat(embedding vector_cosine_ops);
```

**スケーリング戦略**:
- Nx.Serving で 1 回限りモデル読み込み（メモリ効率）
- pgvector で高速 KNN 検索（PostgreSQL 内）
- 埋め込みは非同期生成ジョブ（GenServer/Task）

---

## 4. UI ライブラリ・コンポーネント

### 決定: Tailwind CSS v4 + Heroicons

**理由**:
- **Tailwind CSS v4**: 設定ファイル不要、自動 tree-shaking、最新アップデート対応
- **Heroicons**: Phoenix に組み込み、アイコン数十個でカバー十分

**設定**:
```css
/* assets/css/app.css */
@import "tailwindcss" source(none);
@source "../js";
@source "../../lib/coto_coto_web";
```

**カスタム コンポーネント設計**:
```elixir
# lib/coto_coto_web/components/card_component.ex
defmodule CotoCotoWeb.CardComponent do
  use CotoCotoWeb, :html

  # Reusable card component with Tailwind styling
  attr :card, :map, required: true
  attr :selected, :boolean, default: false
  slot :inner_block

  def card(assigns) do
    ~H"""
    <div class={[
      "absolute border rounded-lg bg-white shadow-md p-4 cursor-move transition-shadow",
      @selected && "shadow-lg ring-2 ring-blue-500"
    ]}
      style={"left: #{@card.x}px; top: #{@card.y}px;"}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
```

---

## 5. 型定義戦略

### 決定: Dialyzer + spec（デフォルト Elixir ツール）

**なぜ外部ツール不要か**:
- Dialyzer は Erlang のデファクト標準
- `@spec` で完全型チェック対応
- Elixir コミュニティが成熟

**実装ルール**:
```elixir
# lib/coto_coto/cards.ex
defmodule CotoCoto.Cards do
  @type card_id :: Ecto.UUID.t()
  @type x :: float()
  @type y :: float()
  @type z_order :: integer()

  @spec move_card(card_id, x, y) :: {:ok, Card.t()} | {:error, String.t()}
  def move_card(card_id, x, y) do
    # 実装...
  end
end
```

**CI/CD チェック**:
```bash
# mix.exs の precommit タスク に追加
mix dialyzer  # 型チェック実行
```

---

## 6. スケーラブルなアーキテクチャ設計

### 6.1 アプリケーション構成

```
lib/coto_coto/
├── application.ex          # OTP 監督ツリー
├── repo.ex                 # Ecto リポジトリ
│
├── schemas/                # Ecto スキーマ
│   ├── user.ex
│   ├── workspace.ex
│   ├── card.ex
│   └── card_embedding.ex
│
├── contexts/               # ビジネスロジック（コンテキスト）
│   ├── accounts.ex         # ユーザー認証
│   ├── workspaces.ex       # ワークスペース管理
│   ├── cards.ex            # カード操作
│   ├── embeddings.ex       # ベクトル埋め込み
│   ├── serendipity.ex      # セレンディピティ・エンジン
│   └── canvas_state.ex     # Z-Index GenServer
│
└── cache/                  # キャッシング層（Phase 2）
    └── redis_cache.ex

lib/coto_coto_web/
├── router.ex
├── endpoint.ex
├── components/
├── live/
└── controllers/
```

### 6.2 OTP 監督ツリー（lib/coto_coto/application.ex）

```elixir
def start(_type, _args) do
  children = [
    CotoCotoWeb.Telemetry,
    CotoCoto.Repo,
    {DNSCluster, query: Application.get_env(:coto_coto, :dns_cluster_query) || :ignore},
    {Phoenix.PubSub, name: CotoCoto.PubSub},

    # Phase 1: Z-Index 状態管理
    {CotoCoto.CanvasState, []},

    # Phase 2: セレンディピティ・エンジン（非同期タスク）
    {Task.Supervisor, name: CotoCoto.TaskSupervisor},

    # Phase 3: 埋め込みキャッシュ（もし Redis 使用）
    # {CotoCoto.RedisCache, []}

    CotoCotoWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: CotoCoto.Supervisor)
end
```

### 6.3 Database スケーリング

**インデックス戦略**:
```sql
-- ホットパス最適化
CREATE INDEX ON cards(workspace_id, z_order DESC);
CREATE INDEX ON cards(updated_at DESC);
CREATE INDEX ON card_embeddings(card_id);
```

**大規模キャンバス対応**:
- LiveView streams 使用（1000+ カード）
- 画面外カード遅延読み込み
- Database クエリ最小化（キャッシング層）

### 6.4 マルチノード展開戦略

**Phase 2**: 複数 Phoenix ノード + Redis

```elixir
# config/prod.exs
config :coto_coto, CotoCoto.PubSub,
  adapter: Phoenix.PubSub.Redis,
  url: System.get_env("REDIS_URL")
```

**冗長性**:
- PubSub: Redis で冗長化
- Database: PostgreSQL レプリケーション
- GenServer 状態: Database から復帰可能

---

## 7. 開発ガイドライン

### コメント・ドキュメント

```elixir
@doc """
カードを新しい座標に移動します。

## 引数
  - card_id: 移動対象のカード ID
  - x: 新しい X 座標（ピクセル）
  - y: 新しい Y 座標（ピクセル）

## 戻り値
  - {:ok, card} 移動成功
  - {:error, changeset} 検証エラー

## 副作用
  - GenServer の z-index を更新
  - PubSub で全クライアントにブロードキャスト
"""
@spec move_card(Ecto.UUID.t(), float(), float()) :: {:ok, Card.t()} | {:error, Changeset.t()}
def move_card(card_id, x, y) do
  # 実装...
end
```

### テスト駆動開発（TDD）

```elixir
# test/coto_coto/cards_test.exs
describe "move_card/3" do
  test "カードを新しい座標に移動する" do
    card = insert!(:card, workspace: workspace)

    {:ok, updated_card} = Cards.move_card(card.id, 100.0, 200.0)

    assert updated_card.x == 100.0
    assert updated_card.y == 200.0
  end

  test "無効な座標では失敗する" do
    card = insert!(:card)

    {:error, changeset} = Cards.move_card(card.id, -100.0, 200.0)

    assert "must be positive" in errors_on(changeset).x
  end
end
```

---

## 8. 外部ライブラリ一覧（Phase 1）

| ライブラリ | バージョン | 用途 |
|-----------|-----------|------|
| phoenix | 1.8+ | Web フレームワーク |
| phoenix_live_view | 最新 | リアルタイム UI |
| ecto_sql + postgrex | 最新 | Database |
| tailwind | v4 | CSS フレームワーク |
| esbuild | 最新 | JS バンドル |
| req | 最新 | HTTP クライアント |
| lazy_html | 最新 | テスト用 HTML パーサー |

**Phase 2 で追加**:
- bumblebee: ベクトル埋め込み
- pgvector: PostgreSQL 拡張

---

## 9. 今後の拡張（参考）

### Offline-First（要検討）
- IndexedDB でクライアント側キャッシュ
- Conflict resolution ロジック

### Real-time 検索
- Elasticsearch / Meilisearch（大規模検索が必要なら）

### 権限管理
- Authorizer パターン（Policies）

---

## ドキュメント履歴

- **2026-03-07**: Issue #2 初版 - 技術選定・アーキテクチャ決定
