# mobile-ide

iPhone から Mac に SSH で入り、tmux 上のターミナルで Claude Code・Codex を操作する iOS アプリ。

MVP（#10 の段階 0〜8）は 2026-09-05 に完了し、MacBook Air をホストに実機で常用できる状態。本番ホストの Mac mini は未着で、到着後の作業は #12 にまとめてある。

## 背景

- Mac mini を 24 時間 / 365 日起動させ、どこからでも開発環境として使えるようにしたい
- 常用端末は折りたたみ iPhone（内側画面 7.8 インチ前後、4:3 に近い比率）を想定
- PC では自作 IDE の [PolePole](https://github.com/nyshk97/ide) を使っている。スマホでも「プロジェクトを選んで端末を開き、Claude Code に頼む」までの動線を同じ感覚で辿りたい
- Claude Code 公式の Remote Control は便利だが、bypass permissions が使えない・`/resume` などターミナル専用コマンドが使えない・Claude の外の素のシェル操作ができない、という制約がある。これらを SSH 経由で補う

## できること

- iPhone を開いて、Mac の既存プロジェクトで Claude Code / Codex に 1 タスク頼み、結果を見て閉じる
- アプリを閉じても Mac 側の tmux セッションは生き続け、次に開いたときに続きが見える。回線が切れても黙って張り直す
- 写真やスクショを Claude に渡せる（チャット入力欄モードでは `@パス ` が入力欄のカーソル位置に入り、文を足して送れる）
- PolePole でピン留めしているプロジェクト一覧をそのまま使う。管理は二重化しない
- iPhone で始めた Claude Code の会話を Mac の PolePole から `claude --resume` で続けられる。逆も同じ（同じホーム・同じ作業ディレクトリなので会話ログを共有できる。#9 で実測）
- 外出先（モバイル回線のみ）からも同じホスト名で繋がる（Tailscale）

## 構成

```
iPhone アプリ                          Mac（開発中は Air、本番は Mac mini）
┌──────────────────────┐              ┌──────────────────────────┐
│ SwiftTerm (端末画面)  │◄─ SSH+PTY ──►│ tmux new-session -A -D    │
│ プロジェクト一覧      │◄─ SSH+exec ─►│ cat projects.json 等      │
│ 画像添付             │── SSH+SFTP ─►│ ~/.claude/uploads/       │
│        ↑ Citadel (SSH client)。接続は用途ごとに張る               │
└──────────┼───────────┘              └──────────────────────────┘
           │ Tailscale (WireGuard)。両端が 100.x.x.x を持つ
           ▼
   iPhone の Tailscale アプリが VPN として常駐
```

- **ネットワーク**: Tailscale。マンション一括回線でポート開放できない前提。iPhone 側は Tailscale アプリを VPN として入れるだけで、本アプリは MagicDNS 名に SSH するだけ。tailnet・マシン名・手順・罠は [docs/tailscale.md](docs/tailscale.md)
- **トランスポート**: SSH（Mac のリモートログイン）。ed25519 鍵をアプリ内で生成して Keychain（この端末限定）に保存し、公開鍵を `authorized_keys` に登録する。ホスト鍵は TOFU（初回信用・以降照合）。パスワード認証はホスト側で切る
- **SSH クライアント**: [Citadel](https://github.com/orlandos-nl/Citadel) 0.12.1（SwiftNIO SSH ベース）。1 接続で多重化できるが、端末の接続は再接続で入れ替わるので、一覧の exec と画像の SFTP は用途ごとに短い接続を張って閉じる
- **端末エミュレータ**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.20.0。将来 libghostty の iOS ターゲットに差し替えられるよう `TerminalSurface` protocol の裏に隠す。マウス追跡中（Claude Code など）の一本指ドラッグが範囲選択になる 1.20.0 の問題は `WheelScrollingTerminalView` で一本指をホイール報告に変えて回避している（upstream PR #657 を含むリリースに上げたら消す。#14）
- **セッション永続化**: tmux。SSH が切れても Mac 側でプロセスを生かす層。ユーザーに tmux のキーバインドは見せず、アプリが `tmux new-session -A -D -s <name> -c <path>` を流すだけ（初回も 2 回目も同じコマンド。`-D` で切れた前の自分を蹴る）。開いたセッションには `set-option mouse on` も流し、素のシェルの一本指スクロールは tmux の copy-mode に任せる
- **プロジェクト一覧**: PolePole の `~/Library/Application Support/polepole/projects.json` を exec で読む。`tmux list-sessions` と突き合わせて作業中のものにマークを付ける

### ホスト側の前提

`scripts/host-setup.sh` が冪等に当てる（sudo が要るので自分の Terminal で流す。詳細は [VERIFY.md](VERIFY.md) の「ホスト」）。

- リモートログイン有効 + 「リモートユーザーにフルディスクアクセスを許可」（dotfiles が `~/Library/CloudStorage/` 配下にあり、sshd から `.zshrc` を読むのに必要）
- sshd はパスワード認証オフ + `ClientAliveInterval 15` / `ClientAliveCountMax 3`（切れた接続の tmux クライアントを 75 秒程度で掃除させる）
- Mac mini では `pmset -a sleep 0 disksleep 0 autorestart 1` と自動ログイン（Claude Code の資格情報がログインキーチェーンにあるため。FileVault はオフ）
- **tmux サーバーは GUI ログインセッションから起動しておく**。sshd から起動されたサーバーの中では Claude Code がキーチェーンを読めず Not logged in になる。無人で起こす仕組みは未解決（#12）
- SSH の exec チャネルは `.zshrc` を読まないので、アプリ側で `PATH=/opt/homebrew/bin:...` を前置きしてからコマンドを流す。端末経路（tmux 内の対話シェル）は影響を受けない

## 画面と操作

1. **接続設定**（歯車）: ホスト名（Tailscale の MagicDNS 名）・ポート・ユーザー名、公開鍵の表示とコピー、鍵の作り直し、ホスト鍵の指紋と忘れる操作、接続テスト。接続先は 1 台固定
2. **プロジェクト一覧**（ホーム）: PolePole のピン順で表示し、その他は最近開いた順。生きている tmux セッションがある行にマーク。タップで端末へ
3. **端末画面**: SwiftTerm 1 枚 + 端末の下に常駐するキーボードバー + チャット入力欄。入力方式は 2 つでプロジェクトごとに記憶する
   - **チャット入力欄（既定）**: ChatGPT / Claude アプリと同じく複数行を書いて送信ボタンで送る（return は改行）。本文は常に bracketed paste で包んで Enter を付けて PTY に流す。tmux がクライアント端末に対して常に bracketed paste を有効にし、ペイン側のモードに合わせて包みを剥がす / 通すので、Claude Code / Codex は複数行を 1 入力として受け、`cat` のようなアプリには素の行が届く。下書きは変わるたびに保存し、開き直しても残る。端末をタップすると入力欄のキーボードが閉じる（端末側にはキーボードを出さない。長押し → Copy は生きる）
   - **直接入力**: 端末がキーボードを持ち 1 キーずつ送る（tab 補完・vim / less・Enter なしの入力用）。日本語入力は確定後にだけ送る
   - Claude Code 起動（`claude --dangerously-skip-permissions`）/ Codex 起動（`codex -a never -s danger-full-access`）
   - git メニュー（`gpull` / `gpush`）/ スラッシュコマンドのメニュー（`/dig` `/plot` `/act` `/retro` `/resume` など。チャット入力欄モードでは入力欄に挿入され、引数を続けて書ける）
   - tab / ^C / 矢印 4 方向（長押しでリピート）/ ⏎ / 入力方式の切替 / キーボード切替（どちらのモードでもキーは PTY に直接届く）
4. **再接続**: 回線断を検出したらバックオフ付きで黙って SSH を張り直し、同じ tmux セッションに attach し直す。フォアグラウンド復帰時と経路変更時（Wi-Fi ↔ モバイル回線）は短い exec で生存を探り、死んでいれば張り直す。バックグラウンドに 60 秒以上いた復帰は探らず張り直す（sshd の ClientAlive で切られているはずで、Tailscale 経由では RST が届かず探ると 3 秒待つ）。再接続中は端末を消さずに薄いバナーだけ出す。tmux 内で exit した正常終了は張り直さない
5. **画像添付**: 写真ピッカーで最大 4 枚選び、長辺 2048px に縮小（写真は JPEG、スクショは PNG のまま）して SFTP で `~/.claude/uploads/` に置き、`@<絶対パス> ` を端末に流し込む。途中で失敗しても成功分だけ流し込む

### 意図的に外しているもの

- diff 表示と push 通知（Claude アプリの Remote Control が持っている。tmux 内で `claude --remote-control` を動かせば同じセッションを Claude アプリで開ける。#9 で実測）
- tmux の window 管理 UI
- ファイルブラウザ、git バッジ、MRU、Cmd+P 相当
- 複数ホスト、設定同期、テーマ
- Mac 側の常駐デーモン（SSH ポーリングで足りている間は不要）

## 残っていること

- **#12 Mac mini 到着後**: 土台 → `host-setup.sh` → Tailscale → アプリの接続先を差し替え → 外出先から実測（スリープしない・DERP から直接に昇格する・再起動後に無人で戻る）。tmux サーバーを GUI ログイン側で無人起動する仕組みもここで決める（LaunchAgent はキーチェーンは読めるが `~/Library/CloudStorage` の読み取りが TCC で止まる）
- **#14 SwiftTerm の更新**: PR #657 を含むリリースが出たら `WheelScrollingTerminalView` を消す

## 開発

XcodeGen + mise。`.xcodeproj` は生成物（gitignore 対象）で、依存は `project.yml` の `exactVersion` で固定する。

```sh
mise run gen          # project.yml → MobileIDE.xcodeproj
mise run boot         # iPhone 17 シミュレータを起動
mise run run          # シミュレータで build → install → launch
mise run test         # ユニットテスト（起動中のシミュレータで）
mise run device-run   # USB 接続した iPhone に build → install → launch
mise run icon         # アプリアイコンを再生成
```

```
MobileIDE/
  App/          エントリポイント
  Core/SSH/     Citadel の接続・PTY・鍵と Keychain・TOFU・再接続ポリシー・SFTP
  Core/Terminal/ TerminalSurface protocol と SwiftTerm 実装、キー定義、ショートカット
  Core/Projects/ projects.json の読み込みと tmux セッション名
  Core/Media/   画像の縮小・変換
  Features/     Home（一覧）/ Terminal（端末・キーボードバー・チャット入力欄・添付）/ Settings
MobileIDETests/ ユニットテスト
scripts/        ホストのセットアップ、自走検証（端末・再接続・添付・チャット入力欄・ClientAlive）、アイコン生成
docs/plans/     段階ごとの plan と実装ログ
```

自走検証は `MOBILE_IDE_HOST` などの環境変数で接続先を注入して起動する。手順・観測点・実機での確認は [VERIFY.md](VERIFY.md)、注意点は [CLAUDE.md](CLAUDE.md)。
