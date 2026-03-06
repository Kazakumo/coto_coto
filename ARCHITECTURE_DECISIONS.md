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

## 10. テスト戦略

### 10.1 テスト駆動開発（TDD）のプロセス

**タスク実装フロー**:
1. **テスト設計書の作成** → チケットに記載
2. **赤（Red）**: テストを書く（失敗を確認）
3. **緑（Green）**: 最小限の実装でテスト合格
4. **リファクタリング（Refactor）**: コードを改善
5. **カバレッジ検証**: C1 100% を確認

### 10.2 テスト設計書の要件

**各チケットに記載すべき項目**:

```markdown
## テスト設計書

### 対象機能
move_card/3 - カードを新しい座標に移動

### テストケース一覧

#### 正常系
- [ ] T1: 有効な座標への移動成功
- [ ] T2: 複数カード同時移動（並行処理）
- [ ] T3: 境界値（0, 最大値）への移動
- [ ] T4: 小数座標への移動

#### 異常系
- [ ] T5: 存在しないカード ID
- [ ] T6: 無効な座標（負数）
- [ ] T7: 空のパラメータ
- [ ] T8: 型不正（文字列座標など）

#### エッジケース
- [ ] T9: 同じ座標への移動（重複）
- [ ] T10: 高速連続呼び出し
- [ ] T11: データベース接続切断時
- [ ] T12: 同時アクセス競合

### カバレッジ目標
- **C1（Statement）**: 100%
- **実行パス網羅**: 全分岐をカバー
```

### 10.3 テストツール・設定

```elixir
# mix.exs
defp project do
  [
    # ...
    preferred_cli_env: [
      test: :test,
      "test.coverage": :test
    ]
  ]
end

defp deps do
  [
    # テスト用
    {:phoenix_live_view_test, "~> 0.0", only: :test},
    {:lazy_html, "~> 0.0"},
    {:excoveralls, "~> 0.0", only: :test},

    # Mock / Stub
    {:mox, "~> 1.0", only: :test},

    # テスト データ生成
    {:ex_machina, "~> 2.0", only: :test},
  ]
end
```

### 10.4 カバレッジ検証スクリプト

```bash
# mix.exs に alias 追加
defp aliases do
  [
    "test.coverage": [
      "coveralls.html",
      "coveralls.detail"
    ]
  ]
end
```

実行:
```bash
mix test.coverage  # HTML レポート生成
mix test --failed  # 失敗したテストのみ再実行
```

### 10.5 テストの分類

#### 単体テスト（Unit Tests）
```elixir
# test/coto_coto/cards_test.exs
defmodule CotoCoto.CardsTest do
  use ExUnit.Case, async: true
  doctest CotoCoto.Cards

  describe "move_card/3" do
    test "有効な座標にカードを移動する" do
      card = insert!(:card)
      {:ok, updated} = Cards.move_card(card.id, 100.0, 200.0)
      assert updated.x == 100.0
      assert updated.y == 200.0
    end

    # その他のテストケース...
  end
end
```

#### 統合テスト（Integration Tests）
```elixir
# test/coto_coto_web/live/canvas_live_test.exs
defmodule CotoCotoWeb.CanvasLiveTest do
  use CotoCotoWeb.ConnCase
  import Phoenix.LiveViewTest

  test "ドラッグでカード位置が更新される" do
    {:ok, view, _html} = live(conn, "/canvas/#{workspace.id}")

    html = render_click(view, "move_card", %{
      "card_id" => card.id,
      "x" => 150,
      "y" => 250
    })

    assert has_element?(view, "[data-testid='card-#{card.id}'][style*='left: 150px']")
  end
end
```

#### システムテスト（System Tests）- 未実装（Phase 2）
```elixir
# test/coto_coto_web/features/canvas_feature_test.exs
# PlayWright や Wallaby で E2E テスト
```

---

## 11. エラーハンドリング設計

### 11.1 エラー分類体系

エラーを3つのカテゴリに分類し、各々の取り扱いを定義します。

#### A. 正常なエラー（Expected Errors）
**定義**: ユーザーの不正操作や、ビジネスロジック上の制約違反

**例**:
- 存在しないリソースへのアクセス
- バリデーション失敗（不正な座標値）
- 権限不足（他人のワークスペース編集）
- 競合エラー（すでに削除されたカード）

**取り扱い**:
- LiveView で `{:error, changeset}` で返す
- ユーザーに分かりやすいエラーメッセージを表示
- ログは info レベル（多数発生予想）

```elixir
def move_card(card_id, x, y) do
  with card <- Repo.get(Card, card_id) do
    case card do
      nil ->
        {:error, "カードが見つかりません"}

      card ->
        card
        |> Card.changeset(%{x: x, y: y})
        |> Repo.update()
    end
  end
end
```

#### B. 異常なエラー（Abnormal Errors）
**定義**: バグ、想定外の状態、ロジックエラー

**例**:
- Database スキーマ不一致
- メモリリーク（GenServer 状態肥大化）
- データベース接続プール枯渇
- 計算オーバーフロー

**取り扱い**:
- `Logger.error/2` で記録
- Sentry / Rollbar へ送信（本番環境）
- ユーザーには「システムエラーが発生しました」と表示
- 管理者アラート発動

```elixir
def move_card(card_id, x, y) do
  try do
    # 実装...
  rescue
    e in Ecto.ConstraintError ->
      Logger.error("Database constraint error: #{inspect(e)}", card_id: card_id)
      {:error, "システムエラーが発生しました"}
  catch
    :exit, reason ->
      Logger.error("Process exit: #{inspect(reason)}")
      {:error, "システムエラーが発生しました"}
  end
end
```

#### C. 想定外のエラー（Unexpected Errors）
**定義**: 外部 API、ネットワーク、リソース枯渇による予測不可能なエラー

**例**:
- ネットワークタイムアウト（埋め込み API）
- Redis 接続切断
- ディスク容量不足
- CPU 過負荷

**取り扱い**:
- リトライ戦略（Exponential Backoff）
- 適切なタイムアウト設定
- フェイルセーフ（デグラデーション）
- ログと監視（Prometheus メトリクス）

```elixir
def generate_embedding(text) do
  Req.get!(embeddings_url, json: %{text: text})
  |> then(&{:ok, &1.body})
rescue
  e in Req.TransportError ->
    Logger.warn("Embedding API timeout, fallback to default", error: inspect(e))
    {:error, :timeout, use_fallback: true}
end
```

### 11.2 エラーパターン洗い出し（全機能共通）

**各コンテキストで洗い出すべきエラー**:

#### Cards コンテキスト

```markdown
### move_card/3

#### 正常なエラー
- ERR001: カードが存在しない
- ERR002: 座標値が範囲外（負数）
- ERR003: 座標値が上限超過（Canvas サイズ）
- ERR004: ワークスペース削除済み（親リソース喪失）
- ERR005: ユーザー権限なし

#### 異常なエラー
- ERR101: Ecto スキーマ変更不備
- ERR102: Database 接続エラー
- ERR103: メモリ不足（GenServer 状態肥大化）

#### 想定外のエラー
- ERR201: Database タイムアウト
- ERR202: Disk I/O エラー
- ERR203: Z-Index GenServer クラッシュ

### Response Mapping

| エラーコード | HTTPStatus | LiveView応答 | ログレベル | ユーザー表示 |
|-----------|-----------|-----------|----------|-----------|
| ERR001-005 | 400, 403, 404 | {:error, message} | info | 日本語メッセージ |
| ERR101-103 | 500 | {:error, "システムエラー"} | error | generic |
| ERR201-203 | 503 | {:error, "一時的なエラー"} | warn | リトライ指示 |
```

### 11.3 エラーハンドリング実装テンプレート

```elixir
# lib/coto_coto/error_handler.ex
defmodule CotoCoto.ErrorHandler do
  @type error_class :: :expected | :abnormal | :unexpected
  @type error_info :: %{
    code: String.t(),
    class: error_class,
    message: String.t(),
    context: map()
  }

  def classify_error(error) do
    case error do
      {:not_found, _} -> :expected
      {:validation, _} -> :expected
      {:unauthorized, _} -> :expected
      {:database_error, _} -> :abnormal
      {:timeout, _} -> :unexpected
      _ -> :unexpected
    end
  end

  def handle_error(error, context \\ %{}) do
    class = classify_error(error)

    case class do
      :expected ->
        log_expected(error, context)
        {:error, user_message(error)}

      :abnormal ->
        log_abnormal(error, context)
        send_alert(error, context)
        {:error, "システムエラーが発生しました"}

      :unexpected ->
        log_unexpected(error, context)
        start_retry(error, context)
        {:error, "一時的なエラーが発生しました。しばらく後にお試しください"}
    end
  end

  defp log_expected(error, context) do
    Logger.info("Expected error: #{inspect(error)}", context)
  end

  defp log_abnormal(error, context) do
    Logger.error("Abnormal error: #{inspect(error)}", context)
  end

  defp log_unexpected(error, context) do
    Logger.warn("Unexpected error: #{inspect(error)}", context)
  end

  defp send_alert(error, context) do
    # Sentry / Rollbar へ送信
    {:ok, _} = Sentry.capture_exception(error, extra: context)
  end

  defp start_retry(error, context) do
    # Task.Supervisor で非同期リトライ
    Task.Supervisor.start_child(
      CotoCoto.TaskSupervisor,
      fn -> retry_with_backoff(error, context) end
    )
  end

  defp retry_with_backoff(error, context, attempt \\ 0, max_attempts \\ 3) do
    if attempt >= max_attempts do
      Logger.error("Retry exhausted: #{inspect(error)}")
    else
      :timer.sleep(:math.pow(2, attempt) * 1000 |> round())
      # リトライ処理...
    end
  end

  defp user_message(error) do
    case error do
      {:not_found, resource} -> "#{resource}が見つかりません"
      {:validation, field} -> "#{field}が無効です"
      {:unauthorized, _} -> "このアクションを実行する権限がありません"
      _ -> "エラーが発生しました"
    end
  end
end
```

### 11.4 エラーハンドリング設計書テンプレート

**各チケットに記載すべき項目**:

```markdown
## エラーハンドリング設計書

### エラーパターン一覧

#### 正常なエラー（Expected）
| コード | エラー内容 | HTTP Status | 対応 |
|------|---------|-----------|------|
| ERR001 | カード未発見 | 404 | ユーザーに通知、戻る |
| ERR002 | 座標値無効 | 400 | バリデーションメッセージ表示 |
| ERR003 | 権限なし | 403 | アクセス拒否メッセージ |

#### 異常なエラー（Abnormal）
| コード | エラー内容 | 原因 | 対応 |
|------|---------|------|------|
| ERR101 | DB スキーマエラー | バグ / 不整合 | alert + ログ記録 |
| ERR102 | Pool 枯渇 | コネクション漏洩 | alert + 自動再起動 |

#### 想定外のエラー（Unexpected）
| コード | エラー内容 | 原因 | 対応 |
|------|---------|------|------|
| ERR201 | API タイムアウト | ネットワーク | リトライ（Exponential Backoff） |
| ERR202 | Redis 接続不可 | インフラ | フェイルセーフ + ログ |

### テスト設計
- [ ] 各エラーパターンをモック / スタブで発生させたテスト
- [ ] エラーメッセージの正確性確認
- [ ] リトライ動作確認
- [ ] ログ出力確認
```

---

## 12. タスク完了の要件

### 12.1 実装フェーズ

各機能実装時は以下を **すべて完了** すること：

1. **テスト設計書作成** → チケットコメントに記載
   - テストケース一覧（正常系・異常系・エッジケース）
   - カバレッジ目標（C1 100%）

2. **エラーハンドリング設計** → チケットコメントに記載
   - エラーパターン洗い出し（正常・異常・想定外）
   - 各エラーの取り扱い規定

3. **TDD で実装**
   - テスト → 実装 → リファクタリング

4. **C1 100% 達成**
   ```bash
   mix test.coverage  # すべてのパスをカバー
   ```

5. **すべてのテストが PASS**
   ```bash
   mix test  # 0 failures
   ```

### 12.2 PR マージ条件

- [ ] テスト設計書がチケットに記載
- [ ] エラーハンドリング設計書がチケットに記載
- [ ] `mix precommit` パス（形式・型チェック・テスト）
- [ ] C1 100% 達成確認
- [ ] Dialyzer 型チェックパス
- [ ] コードレビュー承認
- [ ] チケット `Closes #<NUMBER>` で参照

---

## ドキュメント履歴

- **2026-03-07**: Issue #2 初版 - 技術選定・アーキテクチャ決定
- **2026-03-07**: テスト戦略・エラーハンドリング設計追記
