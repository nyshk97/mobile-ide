# 動作確認

## 環境

- Xcode 26.6（`.mise.toml` の `[env]` で `DEVELOPER_DIR` を Xcode.app に固定）
- bundle id: `com.d0ne1s.mobileide`
- ターゲット: iPhone（iOS 17.0+）
- 実機署名: Team `VYDUR99LAM` の自動署名（Vid と同じ）

## セットアップ

`project.yml` を編集したら必ず再生成する。ユニットテスト（`MobileIDETests`。parse・セッション名など純粋なロジック）は `mise run test`（起動中のシミュレータで `xcodebuild test`）。

`mise run test` が `IndexError: list index out of range` のトレースバックで落ちるときは、シミュレータが起動していない（UDID を取る 1 行スクリプトが空のリストを引いている）。`mise run install` も `BUILD SUCCEEDED` のあと install だけ黙って失敗する。`mise run boot` で起動してからやり直す（2026-09-05 に実例）。

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

### 準備（sudo が要る・冪等）

```sh
bash scripts/host-setup.sh --skip-power --skip-autologin   # ノート（Air）。Mac mini はフラグ無し
bash scripts/host-setup.sh --dry-run                        # 書かずに判定だけ（Claude Code のセッションからはこれ）
```

自分の Terminal で流す（sudo のパスワードを聞かれる。`systemsetup` はそのターミナルアプリにフルディスクアクセスが要る）。やること: sshd の `/etc/ssh/sshd_config.d/00-mobile-ide.conf`（パスワード認証オフ + `ClientAliveInterval 15` / `ClientAliveCountMax 3`）・リモートログイン・電源（`pmset -a sleep 0 disksleep 0 autorestart 1`）・自動ログイン・Brewfile（tmux / Tailscale / PolePole / Claude / Codex）・Claude Code CLI（mise の node に npm で入れる）。土台（Dropbox・Homebrew・mise・dotfiles）は先に済んでいる前提で、無ければステップ 0 で列挙して止まる。

各ステップが `step=<名前> result=changed|unchanged|skipped|unknown|failed` を 1 行出し、最後に `changed=<件数>` と「人が続きをやること」（GUI でしかできない項目）が出る。**2 回目の実行で `changed=0` になることが冪等性の判定基準**。`unknown` は sudo 無しで読めなかった項目（`--dry-run` をセッションから流したとき）。`failed` は書いたのに実効値が目的どおりにならなかった項目で、未完了リストに理由が出る。

`ClientAliveInterval` は、切れた接続の sshd-session と tmux クライアントを 45 秒程度で掃除させるため（既定の 0 だと数時間残る）。アプリ側は attach 時に `-D` で古いクライアントを蹴るので無くても動くが、常時稼働のホストでは入れておく。**keepalive を送るのは sshd-session 自身なので、`kill -STOP` した接続はこの設定に関係なく残る**（効きを見るなら下の「ClientAlive の確認」）。

`00-` で置くのは、後から読まれた設定に負けないため（sshd は先に読まれた値が勝つ）。macOS の sshd は接続ごとに launchd が起動するので再起動は不要。スクリプトは書く前後に `sshd -t` を通し、通らなければ退避から戻す（壊れた conf を置くと以後の新規接続が全部失敗し、外出先からは回復できない）。

- System Settings → 一般 → 共有 → リモートログイン の (i) で「リモートユーザーにフルディスクアクセスを許可」を ON にする（`~/.ssh` と dotfiles が `~/Library/CloudStorage/` 配下にあり、sshd から読むのに必要。スクリプトの `step=fda` が判定する）
- 手元の公開鍵を `~/.ssh/authorized_keys` に入れておく（Air では `id_rsa.pub` を登録済み）。アプリの鍵は `step=authorized_keys` が件数を出す

### 確認

```sh
ssh -o BatchMode=yes localhost 'PATH=/opt/homebrew/bin:$PATH; tmux -V && tmux new-session -d -s verify -c /tmp && tmux list-sessions && tmux kill-session -t verify'
ssh -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no localhost true   # Permission denied になること
ssh -o BatchMode=yes -tt localhost 'zsh -ic "which tmux"'   # /opt/homebrew/bin/tmux が出ること（.zshrc を sshd 経由で読めている証明）
```

- 先に `sudo sshd -T | grep -i -E 'clientalive|passwordauth|kbdinteractive'` が `clientaliveinterval 15` / `clientalivecountmax 3` / `passwordauthentication no` / `kbdinteractiveauthentication no` を出すこと（スクリプトも同じ突き合わせをして `failed` にする）。Mac mini では `pmset -g custom` の全セクションで `sleep 0` / `disksleep 0` / `autorestart 1`、`sudo sysadminctl -autologin status` が自分のユーザー
- 1 行目が `tmux 3.x` と `verify: 1 windows ...` を出し、対話なしで通ること（BatchMode なのでパスワードを聞かれると失敗する）
- 2 行目が `Permission denied (publickey)` で落ちること（パスワード認証が閉じている証明）
- 3 行目で tmux のパスが出ること。exec チャネル（1 行目）は `.zshrc` を読まないので PATH 前置きが必須。PATH 無しだと `command not found: tmux` になる（2026-09-04 に Air で実測）
- iPhone からは Tailscale の MagicDNS 名 `tsubasamacbook-air.tail9fb38b.ts.net` に接続する（Mac 側で `Tailscale status --json` の `Self.DNSName`。Wi-Fi でもモバイル回線でも同じ名前）。2026-09-05 より前は同じ Wi-Fi 上の `tsubasanoMacBook-Air-4.local`（`scutil --get LocalHostName`）だった
- **端末のプロンプトが素の `user@host dir %` になり mise / starship が `Operation not permitted` を出す**ときは、tmux サーバーが FDA を失っている（sshd 自身は読めていても、起動済みのサーバーは別）。`ssh localhost 'PATH=/opt/homebrew/bin:$PATH; tmux -L probe new-session -d "cat ~/.config/mise/config.toml > /tmp/tcc.out 2>&1"; sleep 1; cat /tmp/tcc.out; tmux -L probe kill-server'` で新サーバーなら読めることを確認し、`tmux kill-server` で作り直す（全セッションが消える。2026-09-05 に実例）
- **tmux 内で `claude` を起動すると「Not logged in · Run /login」になる**ときは、tmux サーバーが sshd から起動されていてログインキーチェーンが閉じている（Claude Code の資格情報はログインキーチェーンにある）。サーバーは GUI ログインセッション側から起動しておく: Mac の Terminal / Claude Code から `tmux new -d -s bootstrap; tmux set -g exit-empty off; tmux kill-session -t bootstrap`（`exit-empty off` でセッションが 0 でもサーバーが残る）。切り分けは `ps -o ppid= -p $(tmux display -p '#{pid}')` の親が launchd で、サーバー起動時の親が sshd だったかどうか（2026-09-05 に実例。Mac mini でどう起こすかは #12。LaunchAgent はキーチェーンは読めるが CloudStorage の読み取りが TCC で止まる → docs/tailscale.md「未解決」）

### ClientAlive の確認

```sh
bash scripts/verify-clientalive.sh --expect gone                # 4 行の conf: 75 秒前後で tmux クライアントと sshd-session が両方消える（既定は最大 90 秒待つ）
bash scripts/verify-clientalive.sh --wait 120 --expect remain   # 陰性対照（ClientAliveInterval 0）: 120 秒待っても両方残る
```

`scripts/ssh-proxy.py` 経由で素の ssh を tmux セッション `clientalive` に attach し、proxy を SIGUSR1 で凍結（ソケットは保ったまま中継停止 = keepalive の応答が返らない）して待つ。`client:` / `sshd-session:` の行で対象を特定してから凍結するので、件数の増減ではなく**その**接続が消えたかで判定する。sudo は要らない。

- 切れるのは 45 秒ではない。OpenSSH は未応答の数が CountMax を**超えた**ときに切るので最短でも 15 × 4 = 60 秒、Air の実測は凍結から 75 秒（`t=75s client=gone sshd=gone`）。60 秒待ちで判定すると偽 FAIL になる（2026-09-05 に踏んだ）。陰性対照は 75 秒より長く待たないと意味が無い
- 2026-09-05 に Air で実測: 4 行の conf で 75 秒で両方消える（PASS expect=gone）。2 行の conf（`ClientAliveInterval` 無し）では 120 秒待っても両方残る（PASS expect=remain）
- アプリのクライアントを刺激に使わない: 再接続時の `-D` で蹴られて設定に関係なく消える。sshd-session を `kill -STOP` しない: keepalive を送るのは sshd-session 自身で、止めるとタイマーごと止まる

## Mac mini 到着前に Air で通したこと（#9）

### Remote Control

tmux 内で起動した Claude Code を、iPhone の Claude アプリ（Remote Control）から操作できるかを見る。アプリが attach する `mobile-ide` とは別の tmux セッションで起動し、tmux 上の操作が混ざらないようにする。

```sh
tmux new-session -d -s rc -c ~/mobile-ide 'claude --remote-control mobile-ide-rc'
sleep 15; tmux capture-pane -p -t rc | grep -v '^$' | tail -15     # セッション名と接続状態が出る
```

- iPhone の Claude アプリ → Code（Remote Control）の一覧に `mobile-ide-rc` が出て、アプリから送った指示が `tmux capture-pane -p -t rc` にも出ること
- 逆に tmux 側（`tmux send-keys -t rc '...' Enter`）で打った内容がアプリに出ること
- 片付けは `tmux send-keys -t rc '/exit' Enter` → `tmux kill-session -t rc`
- 実行主体は Mac 側の `claude` プロセス。Mac がオフラインになるとアプリからは続けられない（復帰すれば再接続する）。iPhone のアプリは Anthropic のサーバーと話すだけなので、この経路には Tailscale は要らない
- 2026-09-05 に Air で実測: アプリのコード → セッション一覧に `mobile-ide-rc`（サブタイトル mobile-ide）が出て、アプリから送った「READMEの1行目を読んで」が tmux の画面にも `❯ READMEの1行目を読んで` → `# mobile-ide` で出た。tmux から `send-keys` で送った文もそのまま応答が返り、アプリ側にも出た（双方向で成立）

### Claude Code の会話を端末間で引き継ぐ

iPhone の tmux で始めた会話を PolePole のターミナルで `claude --resume <uuid>` して続きから話す（逆方向も）。会話は `~/.claude/projects/<cwd をエンコードしたディレクトリ>/<uuid>.jsonl` に落ちるので、同じホーム・同じ作業ディレクトリならどの端末からでも再開できる。

1. Mac 側で目印を作る: `openssl rand -hex 3`（値はどこにも書かない。書くと AI のセッションの jsonl にも入って grep が複数ヒットする）。`date +%s` も控える
2. iPhone のアプリから `mobile-ide` の tmux セッションに入り、`claude` で「合言葉は <目印>、と覚えて」を 1 往復して `/exit`
3. Mac 側で uuid を特定: `grep -l '<目印>' ~/.claude/projects/-Users-d0ne1s-mobile-ide/*.jsonl` のうち、手順 1 の時刻以降に更新されたもの（`find ... -newermt @<epoch>`）。1 件に絞れなければ目印を作り直す。mtime 最新だけでは AI 自身の作業セッションを掴む
4. PolePole で mobile-ide を開き、ターミナルで `claude --resume <uuid>` → 「合言葉は?」で目印が返ること
5. 逆方向: PolePole で `/exit` → iPhone の tmux で `claude --resume <uuid>`（または `claude -r` のピッカー）→ 同じ質問で目印が返ること

- 2026-09-05 に Air で実測: 目印の grep は 1 件だけヒット（AI のセッションには目印を一度も表示していないので混ざらない）。PolePole の `claude --resume <uuid>` と iPhone からの再開の両方で目印が返り、jsonl に 3 往復（iPhone → PolePole → iPhone）が順に追記された（38 行 → 52 行）

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

## キーボードバー（#6 → #13）

端末の下に常駐するバー。並びは `[Claude] [Codex] [git ▾] [/ ▾] | tab ^C | ← ↓ ↑ → ⏎ | キーボード切替`（#13 で esc / ctrl / ⇧tab / `~ / - |` を落とし、起動系を足した）。SwiftTerm 標準のアクセサリは外している。
起動系（Claude = `claude --dangerously-skip-permissions`、Codex = `codex -a never -s danger-full-access`、git メニューの `gpull` / `gpush`）は Enter まで送る。スラッシュメニュー（`/` `/dig` … `/resume`、issue #13 の順）は文字列だけ流し、`/` 以外は末尾に空白を付ける（補完リストを閉じる。Enter は送らない）。定義は `Core/Terminal/Shortcut.swift` の 1 か所。
矢印は DECCKM（アプリケーションカーソルモード）で `ESC [ A` / `ESC O A` を切り替える。モードは SwiftTerm 自身の状態（`getTerminal().applicationCursor`）を読む。RIS（`ESC c`）で戻る経路やチャンク境界は tmux 越しでは見えないので `SwiftTermSurfaceTests` が surface に直接 feed して見る（`mise run test`）。

### 自走検証（シミュレータ）

`MOBILE_IDE_PRESS_KEYS`（DEBUG）でバーの操作を接続後に再現する。名前は `TerminalKey`（`tab` `ctrlC` `up` … バーに無い `esc` も可）、ショートカット（`claude` `codex` `gpull` `gpush`、`/` 始まり）、`keyboard`。**tmux セッションは `form` を使う**（`mobile-ide` は実機や Mac 側の Claude Code が attach していることがあり、`-D` で蹴った上にその Claude に文字列を打ち込んでしまう。2026-09-05 に codex のコマンドを Claude への質問として送った実例）。

```sh
T=/opt/homebrew/bin/tmux; CONN=(--env MOBILE_IDE_HOST=127.0.0.1 --env MOBILE_IDE_USER=d0ne1s --env MOBILE_IDE_OPEN_PROJECT=form)
$T kill-session -t form 2>/dev/null
python3 scripts/console-run.py "${CONN[@]}" --env 'MOBILE_IDE_TERMINAL_TYPE=cat -v\n' \
    --env 'MOBILE_IDE_PRESS_KEYS=/,/dig,gpull,tab,up,enter,ctrlC' --until "KEYS done" --keep
$T capture-pane -p -t form       # `//dig gpull` の行（`/` と `/dig ` は Enter 無しで同じ行に残り、gpull の直後で改行 = Enter）→ 次行 `<tab>^[[A` → `^C` でプロンプト
python3 scripts/console-run.py "${CONN[@]}" --env MOBILE_IDE_PRESS_KEYS=claude --until "KEYS done" --keep; sleep 8
$T capture-pane -p -t form       # Claude Code の画面で `bypass permissions on`
$T send-keys -t form Escape; $T send-keys -t form '/exit' Enter        # C-c 2 回では終わらないことがある。/exit で閉じる
python3 scripts/console-run.py "${CONN[@]}" --env MOBILE_IDE_PRESS_KEYS=codex --until "KEYS done" --keep; sleep 10
$T capture-pane -p -t form       # Codex のプロンプト（`Ask Codex to do anything`）
ps -axo args | grep '^codex '    # `codex -a never -s danger-full-access`（フラグが付いている証拠。画面には出ない）
$T send-keys -t form C-c; sleep 1; $T send-keys -t form C-c; $T kill-session -t form
python3 scripts/console-run.py "${CONN[@]}" --env 'MOBILE_IDE_TERMINAL_TYPE=printf "\\e[?1h"; cat -v\n' --env MOBILE_IDE_PRESS_KEYS=up,enter,ctrlC --until "KEYS done" --keep
$T capture-pane -p -t form       # `^[OA`（DECCKM オンで矢印がアプリケーション列になる）
python3 scripts/console-run.py "${CONN[@]}" --env 'MOBILE_IDE_TERMINAL_TYPE=printf "\\e[?1l"; cat -v\n' --env MOBILE_IDE_PRESS_KEYS=up,enter,ctrlC --until "KEYS done" --keep
$T capture-pane -p -t form       # `^[[A`（オフ）。`KEYS pressed up appCursor=` は true のままでよい（tmux は自分のクライアントには ZLE の smkx に従ったモードを出し、ペインへは自分で正しい列に再送する）
python3 scripts/console-run.py "${CONN[@]}" --env MOBILE_IDE_PRESS_KEYS=keyboard --until "KEYS done" --keep
                                 # TERMINAL size の rows が増える（キーボードが閉じて端末が伸びる）。$T list-clients の高さも追従
mise run shot                    # バーが端末の下にあり、左から Claude（オレンジ）/ Codex / git / `/` のマーク、区切り、tab ^C、区切り、矢印。SwiftTerm 標準の esc / ctrl / tab（灰色）が出ていない
mise run test                    # TerminalKey のバイト列、Shortcut の文字列（\r の有無・末尾空白・メニューの順）
```

- tmux はクライアントからの矢印をキーとして解釈してペインのモードに合わせて再送するので、tmux 越しでは `ESC [ A` / `ESC O A` のどちらを送っても内側のアプリには正しく届く。追跡の正しさは DECCKM をオンにした上の手順で見る
- `cat -v` は cooked モードの tty 越しなので `\r` は `^M` でなく改行として見える（`gpull` の直後で行が変わる）
- git / スラッシュの `Menu` の開閉は `simctl` から押せないので実機で見る（自走では `.shortcut(.gpull)` が `perform` を通ることまで）

### 実機（手で確認）

- 日本語入力: `echo ` のあとに「テスト」と打って変換・確定 → Enter。`echo テスト` が 1 回だけ実行され、未確定のひらがなや重複が残らない（SwiftTerm は未確定文字列を送らない）
- ^C キー: `sleep 100` → 1 タップで止まる
- git のマーク → メニューがバーの上に開く → `gpull` が実行される
- `/` のマーク → 11 個が issue の順で出る → `/dig` → プロンプトに `/dig ` が入り補完リストが閉じている → 続けて文を打って Enter で走る。`/` 単独は補完リストが開く
- Claude のマークで Claude Code が bypass permissions で起動する。Codex のマークで Codex が起動する
- Claude Code: ↑ で履歴、確認プロンプトを矢印と ⏎ で答える
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
python3 scripts/verify-reconnect.py      # 8 シナリオ 13 項目（SUMMARY: 13 / 13 passed、約 5 分）。tmux セッション form を作って途中で kill する
```

- 1: SIGHUP → `lost connection closed` → `reconnecting attempt=1 delay=1` → `connected`。`session_created` が同じで、クライアントは断の後に作られた 1 件
- 2: 中継を止めたまま → `reconnect failed attempt=1..4`（Connection refused）の間隔が 1, 2, 4, 8 秒 → 中継を戻すと attempt=5（15 秒待ち）で `connected`。`/tmp/mobile-ide-reconnecting.png` にバナー
- 3: `MOBILE_IDE_PROBE_AFTER=6` + 凍結 → `probe start` の 3 秒後に `probe dead` → `reconnecting attempt=1 delay=0` → `connected`。凍結中は古い tmux クライアントが残っているので、再接続後に 1 件になれば `-D` が効いている証明
- 4: 凍結なし → `probe ok` だけで `reconnecting` / `lost` が出ない
- 5: `tmux kill-session` → `disconnected shell exited` で止まる。`/tmp/mobile-ide-exited.png` に全面オーバーレイ
- 6: `MOBILE_IDE_CLOSE_AFTER=3` + `MOBILE_IDE_OPEN_TIMES=2` で 2 回開閉 → `TERMINAL wired surface=<id> session=<id>` と同じ id の `surface deinit` / `session deinit` が 2 回分出る。`TERMINAL view released current=… previous=…` は 2 回目で `previous=true`（端末 view は UIKit のキーボードが最後の first responder として 1 個だけ握るので `current` は false になる。1 つ前が解放されていれば積み上がらない）。閉じ方は `onDisappear` でクロージャを外して `surface.tearDown()`（SwiftTerm の `updateUiClosed()`）
- 7: `MOBILE_IDE_RESUME_AFTER=5,90`（接続 5 秒後に「90 秒バックグラウンドにいた」ことにして復帰）→ `TERMINAL lost stale after background 90s` → `reconnecting attempt=1 delay=0` → `connected`。`probe` の行が無く、`list-clients` は `-D` で新しい 1 件。閾値は `ReconnectPolicy.staleAfterBackground`（60 秒 = sshd の ClientAliveInterval 15 × (CountMax 3 + 1)。`scripts/host-setup.sh` の値と対）
- 8: `MOBILE_IDE_RESUME_AFTER=5,10` → `probe ok` だけで `lost` / `reconnecting` が無い
- 検証は `MOBILE_IDE_OPEN_PROJECT=form` で `form` セッションを使う（`MOBILE_IDE_VERIFY_PROJECT` で変更可）。**`mobile-ide` を使うと実機 iPhone が同じセッションに attach しているときに `-D` で蹴り合い、クライアント数の判定が狂う**（2026-09-04 に実例: 幅 57 桁の実機クライアントが混ざった）
- `scripts/verify-terminal.py` の 6 項目も通ること（`-D` を足しても端末の基本が壊れていない）
- 自走では `MOBILE_IDE_PROBE_AFTER` / `MOBILE_IDE_RESUME_AFTER`（DEBUG）で復帰と同じ経路を直接呼ぶ（速くて安定する）。背面に回す経路自体はシミュレータでも `xcrun simctl launch booted com.apple.Preferences`（背面へ）→ `xcrun simctl launch booted com.d0ne1s.mobileide`（前面へ）で再現でき、`TERMINAL background` → `foreground` → `resume background=2s` → `probe ok` が出る（2026-09-05 に実測。シナリオ化は未着手）。経路変更の配線は実機で見る

### 実機

iPhone を触らずに Mac 側から起こせる項目は Mac 側で起こす（2026-09-05 に Tailscale 経由で全部通した）。裏取りは `tmux list-clients -t <session>`（`client_created` が断の後・1 件だけ）と `netstat -an -p tcp | grep '\.22 .*ESTABLISHED'`（接続元が iPhone の 100.x）。devicectl のトンネルは Wi-Fi 経由だと `unavailable` になりがちで、アプリのログは当てにしない。

```sh
PID=$(ps -axo pid,command | grep "sshd-session: d0ne1s@ttys" | grep -v grep | awk '{print $1}' | head -1)
kill -9 $PID      # 回線断: iPhone にバナーが一瞬出て 2 秒で再 attach
kill -STOP $PID   # 無音の断: iPhone で別アプリに切り替えて戻ると生存判定 → バナー → 再 attach。古い sshd は kill -9 で片付ける
( sleep 90 | TERM=xterm-256color script -q /dev/null /opt/homebrew/bin/tmux attach -t mobile-ide ) &   # -D の確認: Mac を 2 クライアント目にしてから kill -9 $PID → Mac 側だけ detach される
```

手で確認する項目:

- モバイル回線 ↔ Wi-Fi を切り替える。Tailscale（WireGuard）が経路を引き継ぐので **SSH 接続は切れずそのまま打てる**のが正常（`Tailscale status` の iPhone の endpoint が公衆 IP ↔ 192.168.x に変わるのに `netstat` の接続が同じ）。バナーが一瞬出て続きに戻るのも OK
- 端末を開いたまま Wi-Fi をオフ → 数秒後オン。バナーが出て、同じ tmux セッションの続きが表示される（`claude` を起動しておくと分かりやすい）
- 別アプリに切り替えて 60 秒以上置いて戻る → 探らずに張り直すので、バナーが一瞬出てすぐ続きが表示される（`TERMINAL background` → `foreground` → `resume background=Ns` → `lost stale after background Ns` → `reconnecting attempt=1 delay=0` → `connected`。復帰から 1 秒台）。10 秒程度で戻ると `probe ok` だけで何も出ない
- 復帰の秒数を測るときは `console-run.py --device <id> … --until NEVERMATCH --timeout 900 --keep` でログを流し、iPhone は USB で繋ぐ（Wi-Fi 経由の devicectl はモバイル回線の回で途切れる）。起点は直前に `TERMINAL background` が出ている `foreground` だけ（通知センターの往復でも `foreground` は出る）。モバイル回線の回は Wi-Fi を切って経路変更の probe が落ち着いてからホームに戻す
- 機内モードを 2 分入れて戻す → 自動で戻る。機内モード中に「今すぐ」を押しても多重にならない（バナーの回数が 1 つずつ進む）
- tmux 内で `exit` → 「セッションを抜けました」で止まり、勝手に作り直されない。「再接続」で新しいセッションが開く
- Mac 側で `tmux attach -t <同じセッション>` してから iPhone で再接続 → Mac 側が detach される（`-D`）

## 画像添付（#8）

端末画面の右上（写真アイコン）から PhotosPicker で最大 4 枚選ぶと、アップロード専用の SSH 接続を張って `~/.claude/uploads/`（無ければ `mkdir -p`）に SFTP で置き、端末に `@/絶対パス ` を枚数分流し込む。写真（HEIC / JPEG）は長辺 2048px の JPEG 品質 0.85、スクショ（PNG）は PNG のまま長辺 2048px。転送中は上端バナー「送信中 n / N」、途中失敗は成功分だけ流し込んで「n 枚送れませんでした」。
目印行: `UPLOAD start n=<選択枚数>` / `UPLOAD progress <i>/<N>` / `UPLOAD put <path> <bytes>` / `UPLOAD done n=<成功> failed=<失敗>` / `UPLOAD failed <reason>` / `UPLOAD typed <text>`。

Claude Code の対話 TUI に `@/Users/.../x.jpg 質問` を 1 文字列で流し込んでもファイル補完に食われず、cwd 外の絶対パスでも許可プロンプトなしに `Read 1 file` して答える（auto mode で確認。2026-09-05）。

### 自走検証（シミュレータ）

`MOBILE_IDE_UPLOAD_FILE=<path>[,<path>]`（DEBUG）でホスト側のファイルを同じ経路で送る。`MOBILE_IDE_UPLOAD_AFTER=<秒>` で発火を遅らせられる（中継の切り替えを挟むため）。tmux セッションは `form`。

```sh
mise run boot && mise run install
python3 scripts/verify-upload.py     # 5 シナリオ 7 項目（SUMMARY: 7 / 7 passed、約 3 分）。テスト画像は scripts/make-test-images.sh が /tmp に作る
```

- 1: JPEG 4000x3000 + PNG 1200x2600 → `UPLOAD put` のパスを `sips` で見ると 2048x1536 の JPEG と 945x2048 の PNG。`typed` は `@jpg @png ` の順で、`tmux capture-pane -t form` に見える
- 2: 壊れたファイルを混ぜる → `done n=1 failed=1`、`typed` は 1 枚だけ。`/tmp/mobile-ide-upload-partial.png` にアラート
- 3: `~/.claude/uploads/` を退避してから → 作られる。2 回目も通る（終わったら戻す）
- 4: `ssh-proxy.py` 経由で接続 → `SIGUSR2`（新規接続だけ拒否）→ `UPLOAD_AFTER=6` の発火で `UPLOAD failed Connection refused`。`TERMINAL lost` は出ない。`/tmp/mobile-ide-upload-failed.png`
- 5: `form` で `claude` を起動してから流し込み → 「この画像に何が写っているか一言で」→ 合成画像の内容（黄色地に赤い MOBILE IDE JPEG）を答える。**tmux サーバーが sshd 起動だと Not logged in で落ちる**（上のホストの節）
- `scripts/verify-terminal.py` 6 / 6、`verify-reconnect.py` 13 / 13 も壊れていないこと

### 実機（手で確認）

- `mobile-ide` を開いて `claude` を起動 → 右上の写真ボタン → 写真 1 枚 → 「送信中 1 / 1」→ プロンプトに `@/Users/d0ne1s/.claude/uploads/….jpg ` → 「この画像を説明して」→ Claude が答える
- スクショ 1 枚 → `.png` で入り、文字が読める答えが返る
- 3 枚まとめて → `@a @b @c ` の順、バナーが 1 / 3 → 3 / 3
- 機内モードで選ぶ → 「画像を送れませんでした」。解除後に選び直せ、端末は切れていない
- `ls -lh ~/.claude/uploads/` で写真が 1MB 前後
