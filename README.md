# twitter-save-fav-imgs
Twitterでファボッた画像や動画をローカルに保存するバッチです
自分用に適当に書いただけなので当てにしないで下さい

## 準備
(自分用なので適当に説明します。ごめんなさい。rubyとtwitterのapiが解らないとさっぱりな説明です。)
1. `save_fav_imgs.rb`の最初の方にある`require`を参考にして適当に`gem install`して下さい。
  ```sh
  # 新し目のrubyならこれだけでいいみたいです
  gem install oauth
  ```
2. `save_fav_imgs.json.sample`を参考にして`save_fav_imgs.json`をrbファイルと同じ場所に作って下さい。
3. `save_fav_imgs.json`で指定したディレクトリを予め作っておいて下さい。

## 使い方
```
# 200件取得(これをcronで定期実行するようにすれば勝手に保存してくれます。)
ruby save_fav_imgs.rb

# 200件 x 10回取得(最初だけこれで過去分を取得したほうがいいかもしれません。)
ruby save_fav_imgs.rb -r 10
```

## コマンドライン引数
### `-r <回数>`
何回APIを投げるか設定します。1回につき最新から200件取得します。デフォルトは1です。(手動で実行するときのみ指定して下さい)
### `-s <秒数>`
1回APIを実行する度にこの秒数だけスリープします。デフォルトは1です。
### `-i <Tweetのid>`
Tweetのidを指定して取得します。ファボってなくても保存します。
### `TweetのURL`
TweetのURLを指定して取得します。ファボってなくても保存します。

## 注意
* 同名ファイルがある場合は保存しません。
