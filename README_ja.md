# Tapper

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Tapper-logo-dark.png">
  <img alt="Tapper" src="Tapper-logo-light.png" width="358">
</picture>

Tapper は、macOS が Apple Magic Mouse に用意していない 2 つの操作を加えます。タップでクリックすることと、2 本指で操作スペースを切り替えることです。切り替え中の画面は指に追従します。どちらも手のひらをマウスに乗せたまま使えます。

バージョン 1.0。macOS 13 以降で動作します。macOS 27 と USB-C の Magic Mouse で開発・テストしています。

[English](README.md) | [中文](README_zh.md) | 日本語

## 機能

### タップでクリック

- マウスの前側 3 分の 2 のどこを**タップ**しても左クリックになります。後ろ側 3 分の 1 のタップは無視されるので、乗せた手のひらでクリックされることはありません。
- すばやく **2 回タップ**するとダブルクリックです。
- **2 本指でタップ**すると、トラックパッドと同じように右クリックになります。2 本の指を同時に置いて同時に離します。時間と動きの制限は 1 本指のタップと同じです。
- **ドラッグ**：1 回タップし、もう一度触れて指を離さずにマウスを動かします。指を離すとドロップします。
- **軽いタップも認識します。** マウスがほとんど感知しないような短く軽い接触でもクリックできます。
- **止めている指は邪魔になりません。** マウスの上で 0.5 秒動かさなかった指は無視されるので、隣の指でそのままタップできます。
- **押し込みも今まで通り。** 普通に押し込むとクリックは 1 回だけで、Tapper がクリックを重ねることはありません。マウスの右側を押し込む右クリックもこれまで通り使えます（**システム設定 → マウス → 副ボタンのクリック**）。右側のタップでの右クリックは初期設定でオフです（[詳細設定](#詳細設定)を参照）。

### 2 本指で操作スペースを切り替え

2 本指で左右にスワイプします。少し動かすと隣の操作スペースが現れて指に追従し、指を離すと切り替えが完了します。トラックパッドと同じく、指を左に動かすと右側の操作スペースが現れます。

- **手のひらを乗せたままで OK。** 2 本指でスワイプする間、手のひらや手の側面をマウスに乗せておけます。
- **余計なスクロールなし。** Tapper がスワイプを認識すると、ポインタの下のウインドウは横にスクロールしなくなります。
- **1 回のスワイプで 1 つずつ。** 操作スペースが動き始めたあとは、指を離すと必ず切り替わります。その前に指を離せば取り消せます。最初または最後の操作スペースでは切り替わらず、代わりにポインタの下のウインドウが横にスクロールすることがあります。

使う前に、**システム設定 → マウス → その他のジェスチャ** で、システム標準の「フルスクリーンアプリケーション間をスワイプ」をオフにしてください。この設定がオンの間、Tapper は 2 本指スワイプを処理しないので、1 回のスワイプで 2 回切り替わることはありません。

### メニューのその他の機能

- **Pointer Speed**：システム全体のマウス速度を 0 から 8 で調整するスライダです。
- **Sensitivity Settings…**：タップとスクロールの見分け方を調整します。
- **Two-Finger Zoom**（実験的機能、初期設定でオフ）：ピンチズームに対応したアプリで、2 本指をマウスの前方へ動かすと拡大、後方へ動かすと縮小します。
- **Launch at Login** と **Prevent Sleep (Keep Running)**。

## 動作環境

- macOS 13 以降。操作スペースの切り替えは macOS 27 でテストしています。
- Apple Magic Mouse。
- ビルドには Xcode またはコマンドラインツール（`xcode-select --install`）が必要です。ユニットテストの実行には Xcode が必要です。

## インストール

Tapper はソースからビルドします：

```bash
git clone https://github.com/kkkevinky/Tapper.git
cd Tapper
bash install-final.sh
```

スクリプトはユニバーサルアプリ（Apple シリコンと Intel の両対応）をビルドし、実行中のコピーを終了して `/Applications/Tapper.app` としてインストールし、すぐに開くかどうかを（y/N で）たずねます。以前のバージョンは `Tapper_backup_….app` として同じ場所に残ります。インストールせずに新しいビルドを試すには `bash test-and-install.sh --test-only` を実行します。

手動でインストールする場合は、先に Tapper を終了してから：

```bash
bash build.sh
rm -rf /Applications/Tapper.app
ditto build/Tapper.app /Applications/Tapper.app
```

ビルドはすべてアドホック署名なので、新しいビルドをインストールすると macOS が再びアクセシビリティの許可を求めます。

## 初回起動

1. アプリケーションフォルダから Tapper を開きます。メニューバーにマウスのアイコンが表示されます。Dock にはアイコンが出ません。
2. macOS がアクセシビリティの許可を求めます。**システム設定 → プライバシーとセキュリティ → アクセシビリティ** で **Tapper** をオンにしてください。許可から 1 秒以内に Tapper が動き始めます。許可まで 1 分以上かかった場合は Tapper 自身のダイアログが表示されるので、**Retry** を選んでください。
3. Mac の起動時に Tapper も起動したい場合は、メニューで **Launch at Login** をオンにします。
4. 操作スペースを切り替えるには、上記の「フルスクリーンアプリケーション間をスワイプ」をオフにします。

Tapper はクリックとズームのジェスチャを送るためにアクセシビリティの許可を必要とします。タッチの読み取りには Apple の非公開フレームワーク MultitouchSupport を使っています。そのため Mac App Store では配布できず、macOS のメジャーアップデート後に更新が必要になることがあります。

## メニュー

| 項目 | 内容 |
| --- | --- |
| Status | `Running (1 Magic Mouse)`、`Waiting for Magic Mouse`、`Disabled` のいずれかを表示します。 |
| Tap to Click | タップでのクリック（2 本指タップの右クリックを含む）をオン／オフします。起動するたびにオンに戻ります。Two-Finger Zoom がオフのときにこれをオフにすると、操作スペースの切り替えも止まります。 |
| Two-Finger Zoom | ズームをオン／オフします。設定は保存されます。 |
| Launch at Login | ログイン時に Tapper を起動します。 |
| Prevent Sleep (Keep Running) | Tapper の実行中、電源アダプタにつながっていれば Mac がスリープしないようにします（ディスプレイはスリープできます）。初期設定ではオフです。 |
| Pointer Speed | この Mac のすべてのマウスの速度を設定します。**Restore Default** で Tapper を初めて起動したときの速度に戻ります。 |
| Sensitivity Settings… | 下記の設定ウインドウを開きます。 |
| Accessibility Instructions… | 許可の与え方を表示します。 |
| About Tapper / Quit Tapper | |

## 感度設定

スライダを動かすとすぐに反映され、再起動後も保持されます。

| スライダ | 初期値 | 意味 |
| --- | --- | --- |
| Max Tap Duration | 0.35 秒 | これより長い接触はタップとみなしません。 |
| Movement Tolerance | 8 px | タップ中にポインタが動いてよい距離です。 |
| Double-Tap Window | 0.30 秒 | ダブルクリックやドラッグで、2 回のタップの間に許される時間です。 |
| Surface Movement Limit | 4 % | 指がマウスの上でこれ以上動くとスクロールとみなします。 |
| Surface Path Limit | 10 % | 同じく、指が動いた道のりの合計で判定します。 |
| Scroll Velocity Limit | 1.0 /秒 | これより速く動く指はスクロールとみなします。 |
| Min Tap Duration | 0.03 秒 | これより短い接触は無視します。上げるとタップの判定が厳しくなります。 |
| Right-Click Hold Time | 0.16 秒 | タップで右クリックするときに押さえておく時間です。タップでの右クリックがオンのときだけ使われます。 |
| Left/Right Boundary | 60 % | 右クリック側が始まる位置です。タップでの右クリックがオンのときだけ使われます。 |

同じウインドウにズームの設定もあります：**Enable Two-Finger Zoom**、**Reverse zoom direction**、**Zoom sensitivity**（0.5× から 2.0×）。**Reset to Defaults** はすべての値を初期値に戻し、Two-Finger Zoom もオフにします。

## 詳細設定

メニューにまだない設定がいくつかあります。ターミナルで設定してから、Tapper を終了して開き直してください：

```bash
# マウスの右側を少し長めにタップして右クリック（初期設定はオフ）
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.rightTapEnabled -bool true

# 2 本指タップで右クリックしない（初期設定はオン）
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.twoFingerTapEnabled -bool false

# 2 本指スワイプでの切り替え方：dockswipe（初期設定）、instant、hotkey、off
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode -string instant

# スワイプの方向を逆にする
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeInvert -bool true
```

- `dockswipe`：操作スペースが指に追従します。
- `instant`：指が少し動いた時点ですぐに切り替わります。
- `hotkey`：**システム設定 → キーボード → キーボードショートカット → Mission Control** で「左の操作スペースに移動」「右の操作スペースに移動」に割り当てたショートカットを Tapper が押します。

初期値に戻すにはキーを削除します。例：`defaults delete io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode`

## トラブルシューティング

**タップしても反応しない。** **プライバシーとセキュリティ → アクセシビリティ** で Tapper がオンになっているか確認してください。新しいビルドをインストールしたあとは、スイッチをいったんオフにしてからオンにするか、Tapper を削除して `/Applications/Tapper.app` を追加し直してください。状態が `Waiting for Magic Mouse` のままなら、Tapper にアクセシビリティの許可があるか、マウスが接続されているかを確認してください。マウスの後ろ側 3 分の 1 のタップは仕様で無視されます。

**タップするたびに 2 回クリックされる。** ほかのタップクリック用アプリがまだ動いています。そのアプリを終了し、**システム設定 → 一般 → ログイン項目** から外してください。

**2 本指で 2 回タップすると Mission Control が開く。** これはシステム標準の Magic Mouse ジェスチャです。右クリックだけにしたい場合は、**システム設定 → マウス → その他のジェスチャ** で「Mission Control」をオフにしてください。

**2 本指スワイプで操作スペースが切り替わらない。** 「フルスクリーンアプリケーション間をスワイプ」をオフにし（上記参照）、**Tap to Click** がオンになっているか確認してください。最初または最後の操作スペースより先には切り替わりません。

## アンインストール

1. Tapper のメニューで **Launch at Login** をオフにします。ポインタの速度を変えていた場合は、先に **Restore Default** を押してください。
2. Tapper を終了し、`/Applications/Tapper.app` と、その隣にある `Tapper_backup_*.app` を削除します。
3. 必要に応じて **プライバシーとセキュリティ → アクセシビリティ** から Tapper を削除し、`defaults delete io.github.kkkevinky.tapper` で設定を消去します。

## プライバシー

Tapper にはネットワーク通信のコードがなく、どこにもデータを送りません。設定は自身の環境設定に保存し、ジェスチャの詳細はこの Mac の macOS ログ（サブシステム `io.github.kkkevinky.tapper`）に書き込みます。

## クレジットとライセンス

Tapper は Roger Hughes による [Mouse Toucher](https://github.com/slopcore/mousetoucher) をもとにしており、MIT ライセンスで公開しています。詳しくは [LICENSE](LICENSE) をご覧ください。

2 本指での操作スペース切り替えには、InstantSpaceSwitcher、FasterSwiper、palmpad のコードを改変して使用しています。各ライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります。

MultitouchSupport フレームワークを解析し、資料にまとめてくれたすべての方に感謝します。
