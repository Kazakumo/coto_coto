# CotoCoto
## アイデア発酵ワークスペース
「思考の整理学（外山滋比古著）」の思考を「見つめる、寝かせる、発酵させる」というプロセスに着想を得てデジタルの速さとアナログの手触りで再現
「カチャカチャ」とカードを触る感触と、データを「コトコト」煮込んで発酵させるイメージ。
# 1. 「手触り」を再現するライブ・キャンバス
## フリーレイアウ
- 決まったグリッドではなく **絶対座標** でカードを配置
## ドラッグ＆ドロップの同期
- **Phoenix.Presence** を使用
- 他ユーザーがカードを掴んでいる場合 
  - 「その人の色」でハイライト
  - リアルタイムでカードの軌跡が見える

## 重なり（Z-Index）の管理
- **GenServer** で状態保持
- 例 
  - 古いカードは下  
  - 新しいカードは上  
  - 重要なカードは手前 
# 2. 「寝かせる・浮かべる」の自動化
## 発酵タイマー
一定期間触っていないカードに対して：
- キャンバス端に「浮かぶ」
- 色が少しずつ変化（熟成の視覚化）
## セレンディピティ・エンジン
AIを利用してアイデアの偶然の出会いを作る。

- 関連キーワードを持つ過去カードを検索
- 自動で近くに「フワッ」と寄せる
- 使用技術 
  - Nx（これは使いたい）
  - instructor_ex
  - ベクトル検索

# 3. デジタルならではの整理術

## 「鳥の目」と「虫の目」
**LiveViewのリアクティブ性**を活用

ズームアウトすると：

- カード → ドット（点）表示
- ジャンル分布 → **ヒートマップ的可視化**

## 自動フォルダリング

- カードを「囲む」操作
- 一瞬で **スタック（束）** にまとめる
- スムーズなアニメーション付き

# LiveViewでどこまでリッチにできるか？

「LiveViewはもっさりしているのでは？」という懸念に対して。

最近のアップデートにより：

- JSコマンド
- クライアントサイド Hook

が強化され、かなりリッチな操作が可能。

### 低遅延ドラッグ

- 描画計算 → ブラウザ(JS)
- 位置確定 → Elixirサーバー
→ ネイティブアプリに近い操作感

### CSSアニメーションとの融合
LiveViewから制御可能：
- カード重なりエフェクト
- 並び替え時のスムーズ移動 
  （**FLIPアニメーション**）
# 開発の第一歩：技術スタック（暫定的に考えただけで全くこだわりはない。そもそもここから検討したい）

このアプリをリッチにする「特製レシピ」
| 機能 | 使う道具 | 理由 |
|-----|-----|-----|
| カード座標管理 | GenServer | DB書き込み前にメモリ上で高速計算 |
| 複数人同時編集 | Phoenix Channels | 誰かがカードを投げたら全員に反映 |
| カード自動整理 | Flox / Nx | ベクトル検索で近いカードを引き合わせる |
| UIコンポーネント | Tailwind CSS + Lucide Icons | 洗練された「道具感」のあるUI |


# 実装で必ず守ること
- テスト駆動開発を採用する。
- ソフトウェアアーキテクチャとしてはたとえ大規模にスケールしたときにも採用できるようなelixir/phoenixframeworkにおけるベストプラクティスを採用する
- 型定義は必ずのこすこと
- 本プロジェクトはtypescript/kotlinでnative, web frontendを開発しているelixirに慣れていない開発者があとから必ず参加するものとして、初心者のキャッチアップコストが可能な限り低くなるように、コメントを丁寧に残すこと。
- conventional commitを採用する。feat(issue-xxx): description
- ユーザーとのコミュニケーションは日本語で行うこと
To start your Phoenix server:


* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
