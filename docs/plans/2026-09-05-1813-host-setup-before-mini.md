# Mac mini 到着前にできるホスト側の仕込み（#9 の前半）

## 概要・やりたいこと

#9「Mac mini 到着後のセットアップと外出先からの実測」のうち、ホストが mini である必要のない項目を先に片付ける。ネットワーク層（Tailscale）は 2026-09-05 に済んでいて、残りの mini 固有の作業は別 issue に切り出す。

- ホストのセットアップをスクリプト化し、今の Air に当てて冪等性を確認する（mini では同じスクリプトを流すだけにする）
- tmux 内で `claude --remote-control` を動かし、iPhone の Claude アプリから同じセッションを操作できるか確かめる
- iPhone の tmux で始めた Claude Code の会話を PolePole のターミナルで `claude --resume` して続きから話せるか確かめる（逆方向も）
- #9 を「到着前にできること」の issue に整理し、mini が無いとできない項目だけを新しい issue に移す

GitHub Issue: nyshk97/mobile-ide#9

## 前提・わかっていること

### 決定事項（/dig-lite）

- **セットアップスクリプトは Air にも当てる**。pmset と自動ログインはフラグで飛ばし、sshd 設定と brew bundle は Air で実行する。Air の sshd に `ClientAliveInterval` が入る（#7 では「Air は既定のまま」としていたが、mini と同じ挙動で検証できる方を優先する）
- **PolePole からの再開は会話の再開**。PolePole のターミナルで `claude --resume <id>` して続きから話せれば OK。tmux セッションの共有はやらない（アプリの attach は `-D` で他クライアントを蹴るので衝突する）
- **Remote Control** は tmux 内で `claude --remote-control` を起動し、iPhone の Claude アプリから同じセッションが見えて指示が通れば OK。ホストに依存しないので Air で試す

### 決定事項（polish-plan で決めたこと）

- スクリプトの守備範囲は「Dropbox・Homebrew・mise・dotfiles の同期が済んだ Mac の続きから」（1 回目で決定）。素の Mac の土台は `~/Library/CloudStorage/Dropbox/settings/setup-dotfiles.sh` と Brewfile の既存の運用に任せ、本スクリプトは mobile-ide のホストに固有の部分だけを持つ。前提が欠けていたら人間が先にやることを列挙して即終了する（自前ではインストールしない）
- mini の FileVault はオフ（1 回目で決定。#9 の元の本文に「自動ログイン有効。FileVault はオフになる」と書いてあり、電源断からの無人復帰を優先する）
- Air では pmset と自動ログインを当てない（2 回目で決定。/dig-lite の「フラグで飛ばす」どおり）。ステップ 3・4 の判定ロジックは `--dry-run` をフラグ無しで流して通す。mini 到着当日にこの 2 ステップで手戻りが出る可能性は許容する
- 段階番号は据え置き。#9 は「段階 8」のまま本文とタイトルを書き換え、mini 側の新 issue を「段階 9」にする（#8 = 段階 7 = 画像添付は別セッションが進行中。`docs/plans/2026-09-05-1807-image-upload.md` には触らない）

### 調査で確定した事実

- Air の `/etc/ssh/sshd_config.d/00-mobile-ide.conf` は `PasswordAuthentication no` / `KbdInteractiveAuthentication no` の 2 行だけ。VERIFY.md の printf は `ClientAliveInterval 15` / `ClientAliveCountMax 3` を含んでおり、記述と実体がずれている（書いたつもりが効いていない事故が実際に起きている）
- Air の pmset は `sleep 1` / `disksleep 10`（ノートの既定）。FileVault はオフ。自動ログインは未設定
- Brewfile（`~/Library/CloudStorage/Dropbox/Brewfile`）には `brew 'tmux'` / `cask 'claude'`（デスクトップアプリ）/ `cask 'codex'` / `cask 'tailscale-app'` / `cask 'nyshk97/tap/polepole'` が既にある。**Claude Code の CLI は brew ではなく mise の node（24.13.0）配下の npm グローバル**（`~/.local/share/mise/installs/node/24.13.0/bin/claude`）。codex は `/opt/homebrew/bin/codex`
- `~/.zshrc` も Brewfile も Dropbox の実体への symlink。つまり Dropbox のサインインと同期、Homebrew、mise はスクリプトより前に済んでいる必要がある
- `brew bundle` は Tailscale の pkg が sudo を求めるので Claude Code のセッションからは完走しない。ユーザーの Terminal で流す
- `systemsetup -setremotelogin on` は呼び出し元（Terminal.app）にフルディスクアクセスが無いと失敗する。`-getremotelogin` の読み取りも管理者権限が要る（Claude Code のセッションからは `You need administrator access` で読めない）
- 自動ログインは `sysadminctl -autologin set -userName <user>`（管理者権限が要る。パスワードを聞かれる）。`-autologin status` の読み取りも同様。Tailscale のログイン・リモートログインの FDA トグルも GUI 操作
- macOS の sshd は接続ごとに launchd が起動するので再起動は不要だが、壊れた conf を置くと以後の新規接続が全部失敗する。ホストは外出先からの唯一の入口なので締め出されると回復手段が無い
- `claude --remote-control [name]` が存在する。セッション名の既定プレフィックスはホスト名（`--remote-control-session-name-prefix`）
- Claude Code の会話は `~/.claude/projects/<パスをエンコードしたディレクトリ>/<uuid>.jsonl`。iPhone の tmux で始めた会話も同じ場所に落ちるので、PolePole 側は同じホーム・同じ作業ディレクトリで `claude --resume <uuid>` すればよい。**同じディレクトリに AI 自身の作業セッションの jsonl と `memory/` も同居する**ので、mtime 最新で拾うと自分の会話を掴む
- PolePole は Claude Code のセッション一覧や resume の機能を持たない「ターミナルのワークスペース」。再開は PolePole 内のターミナルで CLI を打つ
- アプリは切断後に自動再接続する（#7）ので、接続が切れると新しい tmux クライアントがすぐ現れる。「消えた」の判定は特定のクライアント（`#{client_created}` と sshd-session の PID）で見ないと偽 pass になる（VERIFY.md 再接続の節に実例）
- **`ClientAliveInterval` の keepalive を送るのは sshd-session 自身**。そのプロセスを `kill -STOP` するとタイマーごと止まるので、設定に関係なく自分では終われない（#7 で「数時間残っていた」のは STOP した接続）。効きを見る刺激は「クライアント側が無言で消える」でなければならない。`scripts/ssh-proxy.py` の SIGUSR1（ソケットを保ったまま中継を止める）がそれで、sshd から見ると keepalive の応答が返らない状態になる
- Tailscale の CLI は `/usr/local/bin/Tailscale`（`/usr/local/bin/tailscale` も同じ）に symlink があり、非対話 bash からも PATH で引ける。実体は `/Applications/Tailscale.app/Contents/MacOS/Tailscale`
- アプリの attach は `tmux new-session -A -D` なので、アプリが張ったクライアントは再接続時に `-D` で数秒で蹴られる。`ClientAliveInterval` の効きを見る対象にアプリのクライアントを使うと、conf が 2 行でも 4 行でも同じ結果になる。刺激の当事者は再接続しない素の ssh にする
- 別セッション（#8 画像添付）がこのワークツリーで `scripts/ssh-proxy.py` / `scripts/console-run.py` / `MobileIDE/**` を未コミットで触っている最中（2026-09-05）。コミットはパス指定で行い、`git add -A` は使わない
- `brew bundle check --file=~/Library/CloudStorage/Dropbox/Brewfile` は Air で satisfied（2026-09-05 に確認）。`~/.ssh/authorized_keys` には末尾が ` mobile-ide` の行が 1 行（実機の鍵）
- mini 到着後に必要な作業（docs/tailscale.md「Mac mini 到着後」）: Mac 側の Tailscale 手順を繰り返し、アプリのホスト名を mini の MagicDNS 名に変えるだけ

### 設計

```
scripts/host-setup.sh        ホストの準備。冪等。引数なしで全部、--skip-power / --skip-autologin で mini 固有の項目を飛ばす。--dry-run で書かずに判定だけ
                             0. 前提チェック: brew / mise / node / Brewfile（--brewfile で上書き可）/ ~/.zshrc の実体が読めるか。欠けていたら「人間が先にやること」を列挙して非ゼロ終了
                             1. sshd: /etc/ssh/sshd_config.d/00-mobile-ide.conf を次の 4 行で置く: PasswordAuthentication no / KbdInteractiveAuthentication no / ClientAliveInterval 15 / ClientAliveCountMax 3
                                （差分があるときだけ。先に sudo sshd -t でベースラインを取る（元から壊れていれば自分の変更と切り分ける）→ 既存を退避 → 書く → sudo sshd -t → NG なら退避から戻して非ゼロ終了
                                → sudo sshd -T の実効値 4 つ（clientaliveinterval 15 / clientalivecountmax 3 / passwordauthentication no / kbdinteractiveauthentication no）を突き合わせ、一致しなければ changed で終わらせず未完了リストへ積む。Include 順で負けているケースはここでしか捕まらない）
                             2. リモートログイン: 現状を読んで off のときだけ systemsetup -setremotelogin on（sudo）。失敗しても abort せず、GUI で ON にするか Terminal.app に FDA を付けるよう案内して続行し、末尾の未完了リストに積む
                             3. 電源: pmset -a sleep 0 disksleep 0 autorestart 1（--skip-power で飛ばす。sudo）
                             4. 自動ログイン: sysadminctl -autologin set -userName $USER（--skip-autologin で飛ばす。パスワードを対話で聞く）
                             5. Brewfile: brew bundle check --file=<Brewfile> が satisfied なら unchanged。満たしていないときだけ brew bundle を流して changed
                             6. Claude Code CLI: mise の node で npm i -g @anthropic-ai/claude-code（既にあれば unchanged）
                             7. GUI でしかできない残り: 判定できるものは ok / 未設定 を出し、判定できないもの（Key expiry の無効化）だけ手作業リストに残す
                                - リモートユーザーの FDA: 2 段で見る。ssh -o BatchMode=yes localhost true が通らなければ unknown と理由（鍵・リモートログインの都合と区別する）。通ったうえで ssh localhost 'cat ~/.config/mise/config.toml' が Operation not permitted にならなければ ok
                                  （CLAUDE.md の「tmux サーバーが FDA を失う」は別物。ここでは sshd から読めるかだけ）
                                - Tailscale: CLI は PATH の Tailscale → 無ければ /Applications/Tailscale.app/Contents/MacOS/Tailscale の順で解決（非対話 bash なので .zshrc に頼らない）。status --json の Self.DNSName が取れれば ok、実体が無ければ 未設定
                                - authorized_keys: ~/.ssh/authorized_keys に末尾が ` mobile-ide` の行が 1 行以上あれば ok。件数も出す（実機とシミュレータの取り違えに気づける）
                             各ステップは「現状を読む → 目的と違うときだけ書く → step=<名前> result=changed|unchanged|skipped|unknown を 1 行出す」の形
                             語彙: changed = 書いた / unchanged = 既に目的の状態 / skipped = --skip-* で飛ばした / unknown = 権限が無くて読めない（--dry-run で sudo 無しのときに出る）
                             理由（なぜ ClientAliveInterval が要るか・なぜ 00- で置くか）はスクリプト冒頭のコメントに書く
VERIFY.md                    「ホスト → 準備」をスクリプト実行に置き換える。理由の段落は残す。自走できる確認（sshd -T の実効値・pmset -g・sysadminctl -autologin status）と、冪等性の判定基準「2 回目は changed が 0 件」を足す
                             「Mac mini 到着前に Air で通したこと」として Remote Control と PolePole 再開の手順を足す
docs/tailscale.md            「Mac mini 到着後」に手順の実体（順序: Dropbox のサインイン → setup-dotfiles.sh → scripts/host-setup.sh → GUI の残り → アプリのホスト名差し替え）を置く。新 issue はこの節をなぞるチェックリストにして、閉じた後も docs だけで再セットアップできるようにする
```

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] iPhone に Claude アプリが入っていて、Air と同じアカウントでログインしていること（Remote Control の確認に使う）
- [ ] iPhone の Tailscale が Connected であること
- [ ] Phase 1 の実行に使うターミナルアプリにフルディスクアクセスが付いていること（`systemsetup` に要る。System Settings → プライバシーとセキュリティ → フルディスクアクセス）
- [ ] sudo のパスワードを手元に

### Phase 0: issue の整理 [AI🤖]
- [x] #10 の現行ロードマップを読んで採番を確定する（#9 = 段階 8 のまま、新 issue = 段階 9）
- [x] 新しい issue「段階 9: Mac mini 到着後」を立て、mini が無いとできない項目だけを移す（docs/tailscale.md「Mac mini 到着後」をなぞるチェックリスト: tailnet 追加・接続先の差し替え・自動ログイン / pmset の適用・数日放置とスリープ・DERP から直接への昇格・外出先からの一覧と端末。手順の実体は docs 側に置く）
- [x] #9 の本文を「到着前にできること」に書き換え、タイトルを「段階 8: ホストのセットアップをスクリプト化して Air で通す」に変える。依存に新 issue を「後続」として書く
- [x] #10 のロードマップに新 issue の行を足す

### Phase 1: セットアップスクリプト [AI🤖]
- [x] `scripts/host-setup.sh` を設計どおりに書く（bash 3.2 で動くこと。全角文字の直後の変数は `${VAR}`。`set -euo pipefail` だがステップ 2 の失敗は握って続行する）
- [x] `--dry-run` をフラグ無しで Claude Code のセッションから流し（書かないので Air の pmset / 自動ログインは変わらない）、Air の現状でステップ 0〜7 の全行が期待どおりに出ることを確認する: precheck=ok / sshd=changed（差分あり）/ remotelogin=unknown（sudo 無し）/ power=changed（sleep 1 → 0）/ autologin=unknown（sudo 無し）/ brew=unchanged（check が satisfied）/ claude-cli=unchanged / fda=ok / tailscale=ok / authorized_keys=ok（1 件）。続けて `--dry-run --skip-power --skip-autologin` で power / autologin が skipped になることも見る
- [x] VERIFY.md「ホスト → 準備」をスクリプト実行に置き換え、確認の節に `sshd -T | grep -i -E 'clientalive|passwordauth'` と `pmset -g` / `sysadminctl -autologin status` の期待値、冪等性の判定基準を書く
- [x] docs/tailscale.md「Mac mini 到着後」を設計どおり寄せる

### Phase 1 の実行 [人間👨‍💻]
- [x] 自分の Terminal で `bash scripts/host-setup.sh --skip-power --skip-autologin` を流す（sudo のパスワードを聞かれる。brew bundle で Tailscale の pkg が sudo を求めることがある）
- [x] もう一度同じコマンドを流し、`result=changed` の行が 0 件で終わることを確認する（冪等性）

### Phase 2: Air での確認 [AI🤖]
- [x] `sshd -T` で `clientaliveinterval 15` / `clientalivecountmax 3` / `passwordauthentication no` が実効値になっていることを確認する
- [x] VERIFY.md「ホスト → 確認」の 3 行を通す
- [x] `git status` で `scripts/ssh-proxy.py` に差分が出ていないか見る（#8 が触っている。出ていれば SIGUSR1 の「ソケットを保ったまま中継停止」の挙動が前提どおりか読んでから使う）
- [x] Mac 側から `scripts/ssh-proxy.py`（127.0.0.1:2222 → 22）経由で**素の ssh** を張って tmux に attach し（専用に `tmux new-session -d -s clientalive -c /tmp` を先に作る。VERIFY.md の `verify` は使い捨てで衝突する。`( sleep 120 | TERM=xterm-256color script -q /dev/null ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes localhost -t 'tmux attach -t clientalive' ) &` の形で stdin を繋いで背景実行。known_hosts は `[localhost]:2222` で別エントリになるので accept-new が要る。VERIFY.md 再接続・実機の `-D` 確認と同じ手口。アプリは使わない: 再接続時の `-D` に蹴られて設定に関係なく消える）、`tmux list-clients -F '#{client_tty} #{client_pid} #{client_created}'` の該当行とその接続の `sshd-session` の PID を控えてから proxy に SIGUSR1 を送って中継を止め、45 秒程度で**その**クライアントが `list-clients` から消え、かつ sshd-session の PID が `ps -p` から消えることの両方を確認する（`ClientAliveInterval` が効いている証明。sshd-session が消えるのは keepalive のタイムアウトでしか起きないので `-D` の detach と区別できる。sshd-session を `kill -STOP` するのは keepalive のタイマーごと止めるので刺激にならない）。終わったら proxy の凍結を解除して止め、`tmux kill-session -t clientalive` で片付ける
- [x] [人間👨‍💻 sudo 2 回] 修正前にこの検査が FAIL することを見る: ユーザーの Terminal で `00-mobile-ide.conf` を 2 行の HEAD 相当に戻してもらい、同じ手順で 45 秒後もクライアントと sshd-session が残ることを確認する。戻しは `bash scripts/host-setup.sh --skip-power --skip-autologin` を流して `sshd=changed` が 1 件出ることで行う（「差分あり → 書く → 実効値の突き合わせ」の経路をもう一度通すことにもなり、戻し忘れも防ぐ）

### Phase 3: Remote Control [AI🤖 + 人間👨‍💻]
- [x] [AI🤖] Air の tmux で `claude --remote-control mobile-ide-rc` を起動する手順を VERIFY.md に書く（アプリが attach する `mobile-ide` セッションとは別の tmux セッションで起動し、tmux 上の操作が混ざらないようにする。jsonl の置き場は cwd で決まるので `~/mobile-ide` で起動すれば Phase 4 と同じディレクトリに落ちる。Phase 4 の絞り込みは目印＋時刻の 2 条件なので混ざっても拾える。今回は Mac 側から `tmux send-keys` で起動してもよい。iPhone のアプリから起動するのは mini 到着後の実測に回す）
- [x] [人間👨‍💻] iPhone の Claude アプリでそのセッションが見え、アプリから送った指示が tmux 側の画面にも出ることを確認する。逆に tmux 側で打った内容がアプリに出るかも見る
- [x] [AI🤖] 結果を VERIFY.md と #9 に記録する。成立しなければ何が出たかを控えて止める（アプリ側の対応を判断するのは別 issue）

### Phase 4: PolePole で会話を再開 [AI🤖 + 人間👨‍💻]
- [x] [AI🤖] 目印を実行時に生成する（`openssl rand -hex 3` の 6 桁）。**plan や VERIFY.md に値を書かない**（書くと AI 自身のセッションの jsonl に同じ文字列が入り grep が複数ヒットする）。開始時刻も控える
- [x] [人間👨‍💻] iPhone のアプリから mobile-ide の tmux セッションに入り、`claude` で「合言葉は <目印>、と覚えて」を 1 往復だけ話して `/exit` する
- [x] [AI🤖] `~/.claude/projects/-Users-d0ne1s-mobile-ide/*.jsonl` のうち「目印を含む」かつ「開始時刻以降に更新された」の 2 条件で uuid を特定する（mtime 最新だけでは自分の作業セッションを掴む。1 件に絞れなければ止めて目印を作り直す）
- [x] [人間👨‍💻] PolePole で mobile-ide を開き、ターミナルで `claude --resume <uuid>` して「合言葉は?」と聞き、続きになっていることを確認する
- [x] [人間👨‍💻] 逆方向: PolePole で始めた会話を `/exit` し、iPhone の tmux で `claude --resume <uuid>`（uuid は Mac 側で控える。iPhone で打ちやすいように `claude -r` のピッカーでも試す）
- [x] [AI🤖] 手順と結果を VERIFY.md に「Claude Code の会話を端末間で引き継ぐ」として書く

### 動作確認 [人間👨‍💻]
- [x] Phase 1 の実行（sudo）
- [x] ~~Phase 2 の陰性対照: conf を 2 行に戻す / `host-setup.sh` で 4 行に戻す（sudo 2 回）~~ 先に撃ったので不要
- [x] Phase 3・4 の実機操作（上に含む）

### 仕上げ [AI🤖]
- [ ] `scripts/host-setup.sh` / `VERIFY.md` / `docs/tailscale.md` / この plan と review-log を**パス指定で**コミットする（`git add -A` は #8 の未コミット作業を巻き込む）
- [ ] #9 のチェックボックスを更新し、`/retro` で残す。特に keepalive の機序（送り手は sshd-session 自身なので `kill -STOP` では見えない・アプリのクライアントは `-D` で蹴られるので刺激に使えない）は CLAUDE.md「ホスト側の癖」に 1 項目として残す。sudo の分岐・brew bundle の罠は VERIFY.md へ

## ログ
### 試したこと・わかったこと
- 2026-09-05: 新 issue は #12。#8（画像添付）は別セッションがコミット済みでワークツリーは自分の変更だけになった
- 2026-09-05: `--dry-run` の実測は期待どおり（precheck=ok / sshd=changed / remotelogin=unknown / power=changed / autologin=unknown / brew=unchanged / claude-cli=unchanged / fda=ok / tailscale=ok / authorized_keys=ok 1 件、changed=2。`--skip-power --skip-autologin` で両方 skipped、changed=1）
- 2026-09-05: VERIFY.md の「tmux サーバーが sshd 起動だとキーチェーンを読めない → mini では LaunchAgent（#9）」を受けて LaunchAgent をスパイク。別ソケット `-L probe` の tmux を LaunchAgent（RunAtLoad）で起こすと `security find-generic-password -s 'Claude Code-credentials'` は読めるが、`cat ~/.config/mise/config.toml`（CloudStorage の実体）が返ってこない（プロセスが S 状態で止まったまま。TCC の同意待ちらしい）。スクリプトには入れず #12 の未解決事項にした

### 方針変更
- 2026-09-05: result の語彙に `failed`（書いたが確認で目的の状態にならなかった）を足した。plan では「changed で終わらせず未完了リストへ」としか決めていなかったが、`unknown`（読めない）と区別できないと集計が濁る
- 2026-09-05: tmux サーバーの LaunchAgent は上記の TCC の問題でスクリプトに入れない。#12 で決める
- 2026-09-05: Phase 2 の陰性対照（修正前の conf で残ること）は、Phase 1 の実行前なら conf が 2 行のままなので sudo なしで撃てる。順序を入れ替えて先に取り、ユーザーに「2 行に戻す」を頼まない。手順は `scripts/verify-clientalive.sh` に落とした（VERIFY.md「ClientAlive の確認」）。実測: 60 秒後も `tmux client remain / sshd-session remain` で PASS expect=remain
- 2026-09-05: 動作確認の節の「Phase 2 の陰性対照（sudo 2 回）」は不要になった → **撤回**（下の記録）
- 2026-09-05: Phase 1 の実行はユーザーの Terminal で 1 回目 `sshd=changed`（退避 /tmp/host-setup.GpJwDL）・2 回目 `changed=0`。remotelogin は unchanged（既に on）。実効値の突き合わせもスクリプト内で通過（failed が出ていない）
- 2026-09-05: VERIFY.md「ホスト → 確認」の 3 行は 4 行の conf でも通る（tmux 3.7c / Permission denied (publickey) / /opt/homebrew/bin/tmux）
- 2026-09-05: ClientAlive の陽性検証は最初 60 秒待ちで FAIL（残った）。OpenSSH は未応答が CountMax を超えたときに切るので最短 60 秒、実測は凍結から **75 秒**で tmux クライアントと sshd-session が同時に消えた（2 秒刻みの遷移ログ）。既定の待ちを 90 秒に変更
- 2026-09-05: Remote Control は成立。iPhone のアプリ「コード」一覧に `mobile-ide-rc` が出て、アプリからの指示（総理大臣の質問・README の 1 行目）が tmux の画面に出た。tmux から `send-keys` で送った文も応答が返った（アプリ側にも出たことをユーザーが確認。双方向で成立）
- 2026-09-05: Phase 4 の uuid 特定は 1 発で 1 件（`cfc8e2f8-53b1-4ff0-844e-a9d97c9d2ab9.jsonl`、38 行、開始時刻以降、最初の user メッセージが「合言葉は…覚えて」）。目印を一度も表示していないので AI 自身の jsonl には入っておらず、grep の複数ヒットは起きなかった
- 2026-09-05: Phase 4 成立。PolePole の `claude --resume` と iPhone からの再開の両方で目印が返り、同じ jsonl に 3 往復が追記された（38 → 52 行）
- 2026-09-05: 先に取った陰性対照は 60 秒待ちだったので、75 秒で切れる陽性と比べて証拠にならない。conf を 2 行に戻して 120 秒の陰性対照を取り直す（sudo 2 回をユーザーに依頼。方針変更を撤回）→ 実測: 2 行の conf で 120 秒待っても `client=remain sshd=remain`（PASS expect=remain）。陽性 75 秒 / 陰性 120 秒で効きが確定
