# 動作確認

## 環境

- Xcode 26.6（`.mise.toml` の `[env]` で `DEVELOPER_DIR` を Xcode.app に固定）
- bundle id: `com.d0ne1s.mobileide`
- ターゲット: iPhone（iOS 17.0+）
- 実機署名: Team `VYDUR99LAM` の自動署名（Vid と同じ）

## セットアップ

`project.yml` を編集したら必ず再生成する。

```sh
mise run gen    # = xcodegen generate
```

アイコンを変えたら `scripts/generate-app-icon.swift` を編集して再生成する（light / dark の 1024px を asset catalog に書き出す）。

```sh
mise run icon
```

## シミュレータ

```sh
mise run boot   # iPhone 17 シミュレータ起動
mise run run    # build → install → launch
mise run shot   # スクリーンショットを /tmp/mobile-ide.png に保存
```

確認項目:

- 起動して「接続先が未設定です」のプレースホルダが表示されること
- ホーム画面に金の C 型の耳（青地）のアイコンが出ていること。ダークモードにすると地が濃紺になること

## 実機（iPhone）

iPhone を Mac とペアリング済み（一度 USB で接続して「このコンピュータを信頼」）で、**ロックを解除した状態**で行う。ペアリング後は同一 Wi-Fi 上なら USB 無しでも devicectl の tunnel が張られ、転送できる（2026-09-04 に実証）。ロック中は developer disk image のマウントが `kAMDMobileImageMounterDeviceLocked` で失敗する。

```sh
bash scripts/device-id.sh   # ペアリング済み iPhone の識別子が 1 行出ればよい
mise run device-run         # build → devicectl install → launch
```

- 初回は iPhone 側で「設定 → 一般 → VPN とデバイス管理」から開発者 App を信頼する必要がある場合がある
- 別の iPhone を使うときは `MOBILE_IDE_DEVICE=<識別子> mise run device-run`
- 署名に失敗するときは Xcode で `MobileIDE.xcodeproj` を開き、Signing & Capabilities で Team を選び直す（`project.yml` の `DEVELOPMENT_TEAM` を書き換えて `mise run gen`）

確認項目:

- ホーム画面に「Mobile IDE」の名前でアイコンが並ぶこと
- 起動してプレースホルダ画面が表示されること

## ホスト（開発中は MacBook Air、本番は Mac mini）

アプリから見たホストは sshd + tmux + PolePole の `projects.json` があるだけの SSH サーバー。Mac mini が届くまでは MacBook Air をホストにする（#1）。

### 準備（1 回だけ・sudo が要る）

```sh
sudo systemsetup -setremotelogin on
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/00-mobile-ide.conf
```

`00-` で置くのは、後から読まれた設定に負けないため（sshd は先に読まれた値が勝つ）。macOS の sshd は接続ごとに launchd が起動するので再起動は不要。Claude Code の Bash からは sudo が通らないので Terminal.app で実行する。

- System Settings → 一般 → 共有 → リモートログイン の (i) で「リモートユーザーにフルディスクアクセスを許可」を ON にする（`~/.ssh` と dotfiles が `~/Library/CloudStorage/` 配下にあり、sshd から読むのに必要）
- tmux は Brewfile 経由で入れる（`brew 'tmux'`）
- 手元の公開鍵を `~/.ssh/authorized_keys` に入れておく（Air では `id_rsa.pub` を登録済み）

### 確認

```sh
ssh -o BatchMode=yes localhost 'PATH=/opt/homebrew/bin:$PATH; tmux -V && tmux new-session -d -s verify -c /tmp && tmux list-sessions && tmux kill-session -t verify'
ssh -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no localhost true   # Permission denied になること
ssh -o BatchMode=yes -tt localhost 'zsh -ic "which tmux"'   # /opt/homebrew/bin/tmux が出ること（.zshrc を sshd 経由で読めている証明）
```

- 1 行目が `tmux 3.x` と `verify: 1 windows ...` を出し、対話なしで通ること（BatchMode なのでパスワードを聞かれると失敗する）
- 2 行目が `Permission denied (publickey)` で落ちること（パスワード認証が閉じている証明）
- 3 行目で tmux のパスが出ること。exec チャネル（1 行目）は `.zshrc` を読まないので PATH 前置きが必須。PATH 無しだと `command not found: tmux` になる（2026-09-04 に Air で実測）
- iPhone からは同じ Wi-Fi 上で `tsubasanoMacBook-Air-4.local` に接続する（ホスト名は `scutil --get LocalHostName`）

## SSH スパイク（#2）

Home 右上の「SSH スパイク」（DEBUG ビルドのみ）から、アプリ内生成の ed25519 鍵で 1 接続の exec → PTY → SFTP を試す画面。
`scripts/console-run.py` がアプリを `--console` 付きで起動し、stdout の `SPIKE ...` 行を集める。

### シミュレータ（自走）

```sh
mise run boot && mise run install
python3 scripts/console-run.py                                   # 起動して公開鍵行だけ拾う
python3 scripts/console-run.py --env MOBILE_IDE_SPIKE_AUTORUN=1 --env MOBILE_IDE_SPIKE_HOST=127.0.0.1 --env MOBILE_IDE_SPIKE_USER=d0ne1s --until "SPIKE done"        # 自動で接続テストまで実行
```

1. 1 回目の出力 `SPIKE pubkey ssh-ed25519 ...` を `~/.ssh/authorized_keys` に追記する（2 回起動して同じ鍵が出ること = UserDefaults からの復元）。形式は `ssh-keygen -l -f <公開鍵を書いたファイル>` が `256 SHA256:... (ED25519)` を返せば正しい
2. 登録前に `--until "SPIKE done"` 付きの実行すると `SPIKE connect NG allAuthenticationOptionsFailed` になること（失敗経路の確認）
3. 登録後の `--until "SPIKE done"` 付きの実行で次の 5 行が出ること

```
SPIKE connect OK d0ne1s@127.0.0.1:22 publickey
SPIKE exec OK hello
SPIKE pty OK tmux 3.7c
SPIKE sftp OK /Users/d0ne1s
SPIKE close OK
```

`--keep` を付けるとアプリを終了しないので、続けて `mise run shot` で結果欄のスクリーンショットが撮れる。

### 実機

```sh
mise run device-install
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)"                                              # 公開鍵行を拾う
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_SPIKE_AUTORUN=1 --env MOBILE_IDE_SPIKE_HOST=tsubasanoMacBook-Air-4.local --env MOBILE_IDE_SPIKE_USER=d0ne1s --until "SPIKE done"
```

- 実機の鍵はシミュレータと別なので、実機の公開鍵行も `authorized_keys` に追記する
- **初回接続で iPhone にローカルネットワークの許可ダイアログが出る。許可するまで `connect NG ... No route to host (errno: 65)` になる**（`.local` の名前解決は通っていて IP まで出るので、ネットワーク障害と見誤りやすい）。出ていなければ 設定 → プライバシーとセキュリティ → ローカルネットワーク で Mobile IDE を ON にする
- 環境変数は `DEVICECTL_CHILD_` プレフィックスで渡る（シミュレータは `SIMCTL_CHILD_`）。スクリプトが面倒を見る

## 端末（#3）

Home の「mobile-ide」行から、Air の tmux セッション `mobile-ide`（作業ディレクトリ `~/mobile-ide`）に SwiftTerm で入る。
接続先ホスト・ユーザーはスパイク画面の保存値（`spike.host` / `spike.user`）を流用する。

### 観測点

tmux サーバーは開発中のホスト（今は Air）上の同じユーザーのものなので、この Mac で `tmux` を直接叩けば端末の状態を見られる。

```sh
T=/opt/homebrew/bin/tmux
$T list-sessions -F '#{session_name} created=#{session_created} attached=#{session_attached}'
$T list-clients -t mobile-ide -F '#{client_width}x#{client_height} #{client_termname} created=#{client_created}'
$T send-keys -t mobile-ide 'echo hello' Enter      # アプリ画面に出力が出る（出力経路）
$T capture-pane -p -t mobile-ide                   # アプリから送った入力が届いているか（入力経路）
$T detach-client -s mobile-ide                     # アプリが「切断されました / shell exited」になる
```

アプリの stdout（`--console`）には `TERMINAL size CxR` / `TERMINAL connected ...` / `TERMINAL resized CxR` / `TERMINAL disconnected <reason>` が出る。

### シミュレータ（自走）

```sh
mise run boot && mise run install
/opt/homebrew/bin/tmux kill-session -t mobile-ide 2>/dev/null   # 無い状態から始める
python3 scripts/console-run.py --env MOBILE_IDE_TERMINAL_AUTORUN=1 --until "TERMINAL resized" --keep
python3 scripts/verify-terminal.py                              # 6 項目を一括検証（SUMMARY: 6 / 6 passed）
```

- 1 つ目で `size 54x48` → `size 54x25`（キーボード表示で縮む）→ `connected ... 54x48` → `resized 54x25` の順に出ること。`list-clients` の値が最後の size と一致すること（接続待ちの間に変わったサイズを接続完了時に送っている証明）
- `.zshrc` の読み込みで `connected` から tmux セッションが現れるまで数秒かかる。`connected` 直後に `list-sessions` すると「no server running」になるので、`has-session` が通るまで待つ（verify-terminal.py はそうしている）
- 別プロセスで attach → detach を試すときは、**前のアプリ実体の古いクライアントを掴まない**よう `#{client_created}` が起動時刻以降のクライアントを待つ（古いクライアントに detach を撃つと新しい方が残って偽 fail になる。2026-09-04 に実例）
- `MOBILE_IDE_TERMINAL_TYPE='echo INPUT_OK\n'` を付けて起動すると接続 1 秒後にその文字列を送る（アプリ → PTY → tmux の経路。SwiftTerm のキー → `send` デリゲートは含まない）
- Claude Code の描画は `tmux send-keys -t mobile-ide claude Enter` → 数秒後に `mise run shot`。ロゴ・プロンプト・モード表示・tmux ステータスバーが崩れていなければ OK。`send-keys C-c C-c` で終了

### 実機

```sh
mise run device-install
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_TERMINAL_AUTORUN=1 \
    --env MOBILE_IDE_SPIKE_HOST=tsubasanoMacBook-Air-4.local --env MOBILE_IDE_SPIKE_USER=d0ne1s --until "TERMINAL connected" --keep
/opt/homebrew/bin/tmux list-clients -t mobile-ide -F '#{client_width}x#{client_height} created=#{client_created}'
```

ここまでは自走（iPhone 17 Pro 相当で 57x27）。以下は手で確認する:

- 標準アクセサリ（esc / ctrl / tab / 矢印）が効く。`claude` を起動して Esc で中断、矢印で履歴
- 横向きに回転すると tmux のステータスバーが横幅いっぱいに描き直される（リサイズが届いている）
- 戻るで画面を閉じてもう一度開くと、同じ tmux セッションの続きが見える（`-A`）
