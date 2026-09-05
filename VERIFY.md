# 動作確認

## 環境

- Xcode 26.6（`.mise.toml` の `[env]` で `DEVELOPER_DIR` を Xcode.app に固定）
- bundle id: `com.d0ne1s.mobileide`
- ターゲット: iPhone（iOS 17.0+）
- 実機署名: Team `VYDUR99LAM` の自動署名（Vid と同じ）

## セットアップ

`project.yml` を編集したら必ず再生成する。ユニットテスト（`MobileIDETests`。parse・セッション名など純粋なロジック）は `mise run test`（起動中のシミュレータで `xcodebuild test`）。

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
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nClientAliveInterval 15\nClientAliveCountMax 3\n' | sudo tee /etc/ssh/sshd_config.d/00-mobile-ide.conf
```

`ClientAliveInterval` は、切れた接続の sshd-session と tmux クライアントを 45 秒程度で掃除させるため（既定の 0 だと数時間残る）。アプリ側は attach 時に `-D` で古いクライアントを蹴るので無くても動くが、Mac mini（#9）では入れておく。

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
- iPhone からは Tailscale の MagicDNS 名 `tsubasamacbook-air.tail9fb38b.ts.net` に接続する（Mac 側で `Tailscale status --json` の `Self.DNSName`。Wi-Fi でもモバイル回線でも同じ名前）。2026-09-05 より前は同じ Wi-Fi 上の `tsubasanoMacBook-Air-4.local`（`scutil --get LocalHostName`）だった

## 接続設定と鍵（#4）

歯車 → 設定。接続先（ホスト名・ポート・ユーザー名）は UserDefaults の `connection.*`、秘密鍵は Keychain（この端末限定）、ホスト鍵は TOFU で UserDefaults の `knownhosts.<host>:<port>` に記録する。

### authorized_keys への登録

1. 設定画面の「公開鍵をコピー」（または起動時 stdout の `SSH pubkey ...` 行）で `ssh-ed25519 AAAA... mobile-ide` を取る
2. ホスト側の `~/.ssh/authorized_keys` に 1 行追記する（Air では `~/Dropbox/dotfiles/.ssh/authorized_keys`、権限 600）
3. 設定画面の「接続してみる」が「接続できました」になる

シミュレータの鍵と実機の鍵は別なので、それぞれ登録する。`ssh-keygen -l -f <公開鍵行を書いたファイル>` が `256 SHA256:... (ED25519)` を返せば形式は正しい。

### 自走検証（シミュレータ）

`scripts/console-run.py` の `--env` で接続先を上書きして起動する（上書きは保存されないので毎回渡す）。目印行は `SSH pubkey` / `SSH hostkey trusted|ok|mismatch` / `SSH test OK|NG`。

```sh
mise run boot && mise run install
python3 scripts/console-run.py --until "SSH pubkey"                                  # 公開鍵行。再起動しても同じ鍵が出る（Keychain）
python3 scripts/console-run.py --env MOBILE_IDE_CONNECTION_TEST=1 --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s \
    --env MOBILE_IDE_KNOWNHOST=forget --until "SSH test"                             # → hostkey trusted → test OK
python3 scripts/console-run.py --env MOBILE_IDE_CONNECTION_TEST=1 --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s \
    --until "SSH test"                                                               # → hostkey ok → test OK
python3 scripts/console-run.py --env MOBILE_IDE_CONNECTION_TEST=1 --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s \
    --env "MOBILE_IDE_KNOWNHOST=ssh-ed25519 <アプリ自身の公開鍵の base64>" --until "SSH test" --keep   # → hostkey mismatch → test NG hostKeyMismatch（1 秒以内）
mise run shot                                                                        # アラートに新旧の指紋と「新しい鍵を信用」
python3 scripts/console-run.py --env MOBILE_IDE_CONNECTION_TEST=1 --env MOBILE_IDE_HOST=192.0.2.1 --env MOBILE_IDE_USER=d0ne1s \
    --until "SSH test" --timeout 40                                                  # → 20 秒で「接続がタイムアウトしました」
```

- `trusted` / `ok` の指紋が `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` と一致すること
- `MOBILE_IDE_KNOWNHOST`（DEBUG のみ）は起動時にホスト鍵の記録を消す / 差し替える。**シミュレータの UserDefaults を外から書き換えるのは不安定**（`plutil` で plist を直接編集しても cfprefsd のキャッシュに負ける。`simctl spawn booted defaults write` も再インストール後はアプリのコンテナと別の場所に書かれて効かない）。アプリ自身に操作させる
- 不一致のあと「新しい鍵を信用」で復帰する経路はボタン操作なので実機で手で確認する
- 鍵が Keychain にあること: 旧形式（UserDefaults の `dev.ssh.ed25519.seed`）からの移行は 2026-09-04 にシミュレータ・実機で 1 回ずつ通した（更新前後で同じ公開鍵、`plutil -p` に seed が残らない）。再現するには旧ビルドを入れてから更新する
- アンインストール（`xcrun simctl uninstall booted com.d0ne1s.mobileide`）で Keychain の鍵も消え、次の起動で新しい鍵になる

### 実機

環境変数の上書き（`MOBILE_IDE_HOST` 等）は保存されない。実機で設定を残すには設定画面で手入力するか、DEBUG の `MOBILE_IDE_SAVE_SETTINGS=1` を付けて一度起動して焼き込む（手入力と同じ setter → didSet を通る）:

```sh
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_HOST=tsubasamacbook-air.tail9fb38b.ts.net --env MOBILE_IDE_USER=d0ne1s --env MOBILE_IDE_SAVE_SETTINGS=1 --until "PROJECTS"
```

```sh
mise run device-install
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --until "SSH pubkey"     # 公開鍵行を拾って authorized_keys に登録
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_CONNECTION_TEST=1 \
    --env MOBILE_IDE_HOST=tsubasamacbook-air.tail9fb38b.ts.net --env MOBILE_IDE_USER=d0ne1s --until "SSH test"
```

- 接続先は Tailscale の MagicDNS 名（2026-09-05 に導入。tailnet `tail9fb38b.ts.net`、Air = `tsubasamacbook-air` / 100.117.207.63、iPhone = `iphone184` / 100.119.208.94）。iPhone の Tailscale アプリが Connected であること。**アプリが Tailscale 経由で入っている証明は sshd の接続元が iPhone の 100.x であること**: `MOBILE_IDE_TERMINAL_AUTORUN=1 ... --keep` で端末を張ったまま `netstat -an -p tcp | awk '$4 ~ /\.22$/ && $6=="ESTABLISHED" {print $5}'` → `100.119.208.94.<port>`（`lsof` は root の sshd を見られないので使えない）。**同一 Wi-Fi にいる限り `.local` でも通ってしまうので、外出先想定の決定打は iPhone の Wi-Fi を切ってモバイル回線だけで一覧と端末が出ること**（手で確認）。経路が DERP リレーか直接かは `Tailscale ping 100.119.208.94`（`via DERP(tok)` / `via 192.168.x.x:41641`）で見える。直後は DERP でも数分で直接に昇格する
- `.local` で繋いでいた頃は **初回接続で iPhone にローカルネットワークの許可ダイアログが出て、許可するまで `No route to host (errno: 65)` になった**（`.local` の名前解決は通っていて IP まで出るので、ネットワーク障害と見誤りやすい）。Tailscale の 100.x 宛てなら不要。出ていなければ 設定 → プライバシーとセキュリティ → ローカルネットワーク で Mobile IDE を ON にする
- 手で確認する項目: 設定画面のホスト鍵の指紋が Mac の `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` と一致する / 「鍵を作り直す」→ 新しい公開鍵を登録 → 接続テスト OK / 「このホスト鍵を忘れる」→ 接続テストで再び記録される

## 端末（#3）

Home の「mobile-ide」行から、Air の tmux セッション `mobile-ide`（作業ディレクトリ `~/mobile-ide`）に SwiftTerm で入る。
接続先は設定画面（歯車）の値。自走検証では `MOBILE_IDE_HOST` / `MOBILE_IDE_USER` で上書きする（保存はされない）。

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
python3 scripts/console-run.py --env MOBILE_IDE_TERMINAL_AUTORUN=1 --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --until "TERMINAL resized" --keep
python3 scripts/verify-terminal.py                              # 接続先は MOBILE_IDE_HOST / MOBILE_IDE_USER（既定 127.0.0.1 / d0ne1s）                              # 6 項目を一括検証（SUMMARY: 6 / 6 passed）
```

- 1 つ目で `size 54x48` → `size 54x25`（キーボード表示で縮む）→ `hostkey ok` → `connected ... 54x48` → `resized 54x25` の順に出ること。`list-clients` の値が最後の size と一致すること（接続待ちの間に変わったサイズを接続完了時に送っている証明）
- `.zshrc` の読み込みで `connected` から tmux セッションが現れるまで数秒かかる。`connected` 直後に `list-sessions` すると「no server running」になるので、`has-session` が通るまで待つ（verify-terminal.py はそうしている）
- 別プロセスで attach → detach を試すときは、**前のアプリ実体の古いクライアントを掴まない**よう `#{client_created}` が起動時刻以降のクライアントを待つ（古いクライアントに detach を撃つと新しい方が残って偽 fail になる。2026-09-04 に実例）
- `MOBILE_IDE_TERMINAL_TYPE='echo INPUT_OK\n'` を付けて起動すると接続 1 秒後にその文字列を送る（アプリ → PTY → tmux の経路。SwiftTerm のキー → `send` デリゲートは含まない）
- Claude Code の描画は `tmux send-keys -t mobile-ide claude Enter` → 数秒後に `mise run shot`。ロゴ・プロンプト・モード表示・tmux ステータスバーが崩れていなければ OK。`send-keys C-c C-c` で終了

### 実機

```sh
mise run device-install
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_TERMINAL_AUTORUN=1 \
    --env MOBILE_IDE_HOST=tsubasamacbook-air.tail9fb38b.ts.net --env MOBILE_IDE_USER=d0ne1s --until "TERMINAL connected" --keep
/opt/homebrew/bin/tmux list-clients -t mobile-ide -F '#{client_width}x#{client_height} created=#{client_created}'
```

ここまでは自走（iPhone 17 Pro 相当で 57x27）。以下は手で確認する:

- 標準アクセサリ（esc / ctrl / tab / 矢印）が効く。`claude` を起動して Esc で中断、矢印で履歴
- 横向きに回転すると tmux のステータスバーが横幅いっぱいに描き直される（リサイズが届いている）
- 戻るで画面を閉じてもう一度開くと、同じ tmux セッションの続きが見える（`-A`）

## プロジェクト一覧（#5）

Home に PolePole の `projects.json`（ピン留めは配列順、その他は `lastOpenedAt` 降順）を出し、`tmux list-sessions` と突き合わせて生きているセッションに印を付ける。タップで `tmux new-session -A -s <ディレクトリ名> -c <path>`。取得は SSH の exec 1 往復で、目印行は `PROJECTS loaded pinned=<n> others=<n> alive=<names>` / `PROJECTS failed <reason>`。

### 自走検証（シミュレータ）

```sh
T=/opt/homebrew/bin/tmux
python3 -c "import json; d=json.load(open('$HOME/Library/Application Support/polepole/projects.json'))['projects']; print(sum(p.get('isPinned',False) for p in d), sum(not p.get('isPinned',False) for p in d))"   # 期待する pinned / others
python3 scripts/console-run.py --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --until "PROJECTS" --keep      # loaded の件数が一致。mise run shot でピン順と色を見る
$T new-session -d -s form -c ~/form                                                                                          # Air 側でセッションを作る
python3 scripts/console-run.py --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --until "PROJECTS"             # alive に form が入る（HyperForm の行に緑の点）
$T kill-session -t form
python3 scripts/console-run.py --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --until "PROJECTS"             # alive から消える（「消えた」の前に「あった」を見ている）
python3 scripts/console-run.py --env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --env MOBILE_IDE_OPEN_PROJECT=form --until "TERMINAL connected" --keep
$T display -p -t form '#{pane_current_path}'                                                                                 # /Users/d0ne1s/form（作業ディレクトリが効いている）
python3 scripts/console-run.py --env MOBILE_IDE_HOST=192.0.2.1 --env MOBILE_IDE_USER=d0ne1s --until "PROJECTS" --timeout 40 # failed 接続がタイムアウトしました（一覧の場所に再試行）
mise run test                                                                                                                # parse / apply / TmuxSessionName の 7 テスト
```

- tmux のセッション名は path のディレクトリ名（`[A-Za-z0-9_-]` 以外は `-`）。`.` と `:` は tmux の `-t` で指定できなくなるので必ず置き換える。同名は親ディレクトリ名を後ろに付ける
- **exec の応答でタブが `_` に化ける**（Citadel の exec 経路。OpenSSH クライアント経由では化けない）。tmux の `-F` はタブ区切りにせず、スペース区切りで名前を最後に置く

### 実機

```sh
mise run device-install
python3 scripts/console-run.py --device "$(bash scripts/device-id.sh)" --env MOBILE_IDE_HOST=tsubasamacbook-air.tail9fb38b.ts.net --env MOBILE_IDE_USER=d0ne1s --until "PROJECTS"
```

手で確認する項目: 一覧が PolePole のサイドバーと同じ順・同じ色 / ピン留めの行をタップして tmux に入り、プロンプトの作業ディレクトリがそのプロジェクト / 戻ると行に印 / pull-to-refresh で更新

## キーボードバー（#6）

端末の下に常駐するバー（esc / ctrl / tab / ⇧tab / ^C / ~ / - | / ← ↓ ↑ → / ⏎ / キーボード切替）。SwiftTerm 標準のアクセサリは外している。
Ctrl はワンショット（SwiftTerm の `controlModifier`）。矢印は DECCKM（`ESC [ ? 1 h/l`）を出力から追跡して `ESC [ A` / `ESC O A` を切り替える。

### 自走検証（シミュレータ）

`MOBILE_IDE_PRESS_KEYS`（DEBUG）でバーの操作を接続後に再現し、`cat -v` で制御文字を可視化して tmux 側で読む。

```sh
T=/opt/homebrew/bin/tmux; CONN=(--env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --env MOBILE_IDE_TERMINAL_AUTORUN=1)
python3 scripts/console-run.py "${CONN[@]}" --env 'MOBILE_IDE_TERMINAL_TYPE=cat -v\n' \
    --env MOBILE_IDE_PRESS_KEYS=esc,tab,shiftTab,up,down,left,right,tilde,slash,dash,pipe,enter,ctrlC --until "KEYS done" --keep
$T capture-pane -p -t mobile-ide      # `^[<tab>^[[Z^[[A^[[B^[[D^[[C~/-|` の行と、`^C` のあとにプロンプト（0x03 で cat が終わった）
python3 scripts/console-run.py "${CONN[@]}" --env 'MOBILE_IDE_TERMINAL_TYPE=printf "\\e[?1h"; cat -v\n' --env MOBILE_IDE_PRESS_KEYS=up,enter,ctrlC --until "KEYS done" --keep
$T capture-pane -p -t mobile-ide      # `^[OA`（DECCKM オンで矢印がアプリケーション列になる）
python3 scripts/console-run.py "${CONN[@]}" --env MOBILE_IDE_PRESS_KEYS=keyboard --until "KEYS done" --keep
                                      # TERMINAL size の rows が増える（キーボードが閉じて端末が伸びる）。$T list-clients の高さも追従
mise run shot                         # バーが端末の下にあり、キーボード上に SwiftTerm 標準の esc / ctrl / tab（灰色）が出ていない
mise run test                         # TerminalKey のバイト列（矢印のモード切替・Shift+Tab・Ctrl+C）
```

- tmux はクライアントからの矢印をキーとして解釈してペインのモードに合わせて再送するので、tmux 越しでは `ESC [ A` / `ESC O A` のどちらを送っても内側のアプリには正しく届く。追跡の正しさは DECCKM をオンにした上の手順で見る
- Ctrl ワンショットは SwiftTerm の `insertText` 経路（ソフトウェアキーボード）でしか消費されない。`MOBILE_IDE_TERMINAL_TYPE` は `send(text:)` なので Ctrl が乗らない。**実機で人間が確認する**

### 実機（手で確認）

- 日本語入力: `echo ` のあとに「テスト」と打って変換・確定 → Enter。`echo テスト` が 1 回だけ実行され、未確定のひらがなや重複が残らない（SwiftTerm は未確定文字列を送らない）
- Ctrl ワンショット: `sleep 100` → ctrl（強調表示）→ `c` → 止まって強調が消える。続けて `c` は普通の文字
- ^C キー: `sleep 100` → 1 タップで止まる
- Claude Code: ⇧tab でモード切替、↑ で履歴、esc で入力が消える、確認プロンプトを矢印と ⏎ で答える
- キーボード切替でキーボードが閉じて端末が伸び、バーは残る。横向きでバーが 1 行に収まるか横スクロールできる

## 再接続（#7）

回線断を検出したら `TERMINAL lost <reason>` → `TERMINAL reconnecting attempt=<n> delay=<sec>`（1, 2, 4, 8, 15 秒で頭打ち）→ `TERMINAL connected` と自動で張り直す。端末の描画は消さず上端にバナー（「再接続中… n 回目」+「今すぐ」）を出す。
フォアグラウンド復帰（scenePhase）と経路変更（`NWPathMonitor`、`NETWORK path up|down <interfaces>`）では同じ接続で `true` を exec して生存を探り、3 秒で返らなければ `TERMINAL probe dead` → 遅延なしで張り直す（生きていれば `TERMINAL probe ok` だけ）。
tmux 内のシェルが exit した正常終了は `TERMINAL disconnected shell exited` で止まり、全面オーバーレイの「再接続」ボタンに任せる（自動では張り直さない）。attach は `tmux new-session -A -D` で他クライアントを detach する。

切れ方の分類は Citadel の `client.isConnected`。回線が死んでも inbound はエラーなしで普通に終わるので、終了時に接続が生きていればシェルの exit、死んでいれば回線断とみなす。

### 自走検証（シミュレータ）

sshd と authorized_keys には触らず、`scripts/ssh-proxy.py`（127.0.0.1:2222 → 22 の TCP 中継）に SIGHUP（接続を切る）/ SIGUSR1（凍結: ソケットを保ったまま中継と EOF の伝搬を止める。解除も同じ）/ SIGTERM（止める → 接続拒否）を送って回線断を起こす。

```sh
mise run boot && mise run install
python3 scripts/verify-reconnect.py      # 5 シナリオ 8 項目（SUMMARY: 8 / 8 passed、約 3 分）。tmux セッション form を作って途中で kill する
```

- 1: SIGHUP → `lost connection closed` → `reconnecting attempt=1 delay=1` → `connected`。`session_created` が同じで、クライアントは断の後に作られた 1 件
- 2: 中継を止めたまま → `reconnect failed attempt=1..4`（Connection refused）の間隔が 1, 2, 4, 8 秒 → 中継を戻すと attempt=5（15 秒待ち）で `connected`。`/tmp/mobile-ide-reconnecting.png` にバナー
- 3: `MOBILE_IDE_PROBE_AFTER=6` + 凍結 → `probe start` の 3 秒後に `probe dead` → `reconnecting attempt=1 delay=0` → `connected`。凍結中は古い tmux クライアントが残っているので、再接続後に 1 件になれば `-D` が効いている証明
- 4: 凍結なし → `probe ok` だけで `reconnecting` / `lost` が出ない
- 5: `tmux kill-session` → `disconnected shell exited` で止まる。`/tmp/mobile-ide-exited.png` に全面オーバーレイ
- 検証は `MOBILE_IDE_OPEN_PROJECT=form` で `form` セッションを使う（`MOBILE_IDE_VERIFY_PROJECT` で変更可）。**`mobile-ide` を使うと実機 iPhone が同じセッションに attach しているときに `-D` で蹴り合い、クライアント数の判定が狂う**（2026-09-04 に実例: 幅 57 桁の実機クライアントが混ざった）
- `scripts/verify-terminal.py` の 6 項目も通ること（`-D` を足しても端末の基本が壊れていない）
- scenePhase はシミュレータから起こせないので `MOBILE_IDE_PROBE_AFTER`（DEBUG）で同じ経路を呼ぶ。scenePhase と経路変更の配線は実機で見る

### 実機（手で確認）

- 端末を開いたまま Wi-Fi をオフ → 数秒後オン。バナーが出て、同じ tmux セッションの続きが表示される（`claude` を起動しておくと分かりやすい）
- 別アプリに切り替えて 1 分以上置いて戻る。生きていれば何も出ない、切れていればバナー → 続きが表示される
- 機内モードを 2 分入れて戻す → 自動で戻る。機内モード中に「今すぐ」を押しても多重にならない（バナーの回数が 1 つずつ進む）
- tmux 内で `exit` → 「セッションを抜けました」で止まり、勝手に作り直されない。「再接続」で新しいセッションが開く
- Mac 側で `tmux attach -t <同じセッション>` してから iPhone で再接続 → Mac 側が detach される（`-D`）
