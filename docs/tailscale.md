# Tailscale（ネットワーク層）

2026-09-05 に導入。iPhone と Mac を同じ tailnet に入れ、本アプリは MagicDNS 名に SSH するだけ。マンション一括回線でポート開放できない前提はこれで解消した（モバイル回線のみの iPhone からプロジェクト一覧が出ることを実機で確認済み）。

## 現在の構成

| 項目 | 値 |
|---|---|
| プラン | Personal（無料。ユーザー 3 人・デバイス 100 台まで） |
| ログイン | Google アカウント nyshk97@gmail.com（個人。会社の Workspace で入ると会社ドメインの tailnet になるので注意） |
| tailnet | `tail9fb38b.ts.net`（MagicDNS 有効） |
| Air | `tsubasamacbook-air` / 100.117.207.63 / `tsubasamacbook-air.tail9fb38b.ts.net`。Key expiry 無効化済み |
| iPhone | `iphone184` / 100.119.208.94 |
| 管理画面 | https://login.tailscale.com/admin/machines |

アプリの接続先ホスト名は Air の MagicDNS 名。実機への焼き込みと確認手順は [VERIFY.md](../VERIFY.md) の「接続設定と鍵 → 実機」。

## セットアップ手順（Mac 側）

1. Brewfile（`~/Library/CloudStorage/Dropbox/Brewfile`）に `cask 'tailscale-app'` を足して `brew bundle`。**pkg インストーラが sudo を求めるので、Claude Code のセッションではなく自分の Terminal で実行する**
2. `open -a Tailscale` → ウィンドウの「Sign in to your network」→ ブラウザで Google ログイン →「Connect」
3. 管理画面 Machines で該当マシンの「…」→ **Disable key expiry**（放置すると 180 日で鍵が切れて突然つながらなくなる）
4. `Tailscale status --json` で `Self.DNSName` を控える。これがアプリに入れるホスト名

CLI は `/Applications/Tailscale.app/Contents/MacOS/Tailscale`。`status` / `ping` は使えるが、**`up` / `login` は GUI に委譲する作りで、Claude Code のセッションから叩くと `The Tailscale GUI failed to start (CLIError error 3)` になる**。ログインは GUI を人が押す。

## セットアップ手順（iPhone 側）

1. App Store で Tailscale を入れて開く → Log in → 同じ Google アカウント
2. 「VPN 構成を追加」のダイアログで許可（Face ID / パスコード）。**ここを閉じてしまうと「VPN CONFIGURATION REQUIRED」で止まる**。「Connect」を押せばダイアログが出直す
3. トグルが Connected になり Devices に Mac が緑で出れば完了。以後 VPN として常駐する

## 確認の仕方

- Mac から iPhone: `Tailscale ping 100.119.208.94`。`via DERP(tok)` は東京のリレー経由、`via 192.168.x.x:41641` は直接。接続直後は DERP でも数分で直接に昇格する（SSH はどちらでも通る）
- アプリが Tailscale 経由で入っている証明: sshd の接続元が iPhone の 100.x であること（VERIFY.md 参照。`lsof` は root の sshd を見られないので `netstat`）
- **同一 Wi-Fi にいる限り `.local` でも通ってしまう**ので、外出先想定の決定打は iPhone の Wi-Fi を切ってモバイル回線だけで一覧・端末が出ること

## 罠

- **初回ログインでブラウザ側は成功したのに Mac のアプリが「Not connected」のまま固まった**（管理画面にはマシンが登録されていた）。`osascript -e 'quit app "Tailscale"'` → `open -a Tailscale` で開き直してから再ログインで通った。同じマシン鍵で再登録されるので重複エントリは出なかった
- アプリのオンボーディングが機種名を `macbook-pro` と表示することがあるが、登録される名前はホスト名由来（`tsubasamacbook-air`）。気にしなくてよい
- `.local` で繋いでいた頃は iPhone にローカルネットワークの許可ダイアログが出て、許可するまで `No route to host` になった。100.x 宛てなら不要
- つながらないときはまず iPhone の Tailscale のトグル（iOS 側で VPN を切ると当然落ちる）

## Mac mini 到着後

上の Mac 側手順を mini で繰り返し、アプリの設定画面でホスト名を mini の MagicDNS 名に変えるだけ。Air の Tailscale はそのまま残してよい（別マシンとして共存する）。Tailscale SSH（Tailscale 側の認証で SSH する機能）は使わない。本アプリは自前の ed25519 鍵で `authorized_keys` に入る設計のまま。
