# 接続設定と鍵管理（#4）

## 概要・やりたいこと

#2 のスパイクで仮置きしたもの（UserDefaults の秘密鍵、`spike.host` / `spike.user`、`.acceptAnything()`、スパイク画面）を正式な形にする。

- 秘密鍵を Keychain（この端末限定）に保存する
- ホスト鍵を TOFU（初回信用・以降照合）で固定する
- 歯車から開く設定画面（ホスト名・ポート・ユーザー名、公開鍵の表示とコピー、鍵の作り直し、ホスト鍵の指紋、接続テスト）
- スパイク画面と自走用コードを削除する
- `authorized_keys` への登録手順を VERIFY.md に書く

GitHub Issue: nyshk97/mobile-ide#4。鍵の生成と OpenSSH 形式の公開鍵行は #2 で済んでいる。

## 前提・わかっていること

### 決定事項（/dig-lite）

- **ホスト鍵は TOFU**。初回接続で受け取った鍵を保存し、以降は照合。違っていたら接続を拒否して「ホスト鍵が変わりました」と新旧の SHA256 指紋を出し、「新しい鍵を信用」で上書きできる。Citadel の `.custom(delegate)` で実装
- **秘密鍵は Keychain にこの端末限定**（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）。iCloud Keychain に同期せず、バックアップからも別端末に復元されない。新しい iPhone では鍵を作り直して `authorized_keys` に 1 行足す。AfterFirstUnlock なのは #7 の再接続がロック直後でも動くように
- **鍵ストアは protocol に切る**（`secrets-in-apps.md` の型）。Keychain 実装と、Preview / 検証用のメモリ実装。iOS の Keychain は許可ダイアログを出さないので自走検証は実 Keychain（シミュレータの Keychain）で通す
- **既存インストールの鍵は初回起動で UserDefaults（`dev.ssh.ed25519.seed`）から Keychain へ移し、UserDefaults からは消す**。これで `authorized_keys` の再登録が不要。シミュレータ・実機ともに今まさに旧形式のデータがあるので、移行経路を本物のデータで 1 回ずつ通せる
- **設定画面**は歯車から。ホスト名・ポート（既定 22）・ユーザー名、公開鍵の表示とコピー、「鍵を作り直す」（確認ダイアログ付き）、ホスト鍵の指紋と「忘れる」、接続テスト（exec で `echo ok`）
- **スパイク画面と自走用コード（`SSHSpikeRunner` / `SpikeAutorun` / `SSHSpikeView` / `DevKeyStore`）は削除**。`spike.host` / `spike.user` は `connection.host` / `connection.port` / `connection.user` に改名（開発端末だけなので値の移行はしない。設定画面で入れ直す）
- 起動時に公開鍵行を stdout に出す仕組みは残す（実機の `authorized_keys` 登録を自走するため）。プレフィックスは `SSH pubkey`

### 調査で確定した事実

- `SSHHostKeyValidator` は `.acceptAnything()` / `.trustedKeys(Set<NIOSSHPublicKey>)` / `.custom(NIOSSHClientServerAuthenticationDelegate)`。custom は `validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>)` を実装する
- `NIOSSHPublicKey` は `Hashable`。`init(openSSHPublicKey: String)` で `ssh-ed25519 AAAA...` を読み、`write(to: inout ByteBuffer)` で wire 形式に書ける。指紋は wire 形式の SHA256 を base64（パディング無し）にして `SHA256:` を付ける（OpenSSH と同じ表記）
- ホスト鍵検証に失敗したときに `SSHClient.connect` が投げるエラーの型は未確認（NIOSSH のハンドシェイク失敗として包まれる可能性）。UI に新旧指紋を出す必要があるので、**validator 側で不一致を記録しておき、connect 失敗時にそれを読む**形にして型に依存しない
- シミュレータの UserDefaults は `xcrun simctl get_app_container booted com.d0ne1s.mobileide data` の `Library/Preferences/com.d0ne1s.mobileide.plist`。`plutil -p` で読め、`plutil -replace` / `-insert` で書ける（ホスト鍵の改竄・旧形式 seed の投入に使う）

### 設計

```
Core/SSH/SSHKeyStore.swift        protocol SSHKeyStore { load / save / delete }、KeychainSSHKeyStore（GenericPassword、ThisDeviceOnly）、InMemorySSHKeyStore
Core/SSH/SSHIdentity.swift        @Observable。鍵ストアから読み、無ければ生成して保存。旧 UserDefaults からの移行。publicKeyLine / regenerate()
Core/SSH/KnownHostStore.swift     protocol KnownHostStore { key(for host:port) / set / remove }、UserDefaults 実装（値は OpenSSH 公開鍵行）
Core/SSH/HostKeyFingerprint.swift NIOSSHPublicKey → "SHA256:..." と OpenSSH 行の相互変換
Core/SSH/TOFUHostKeyValidator.swift NIOSSHClientServerAuthenticationDelegate。未登録なら保存して成功、一致なら成功、不一致なら失敗 + lastMismatch に (expected, actual) を記録
Core/SSH/ConnectionSettings.swift @Observable。host / port / user を UserDefaults（connection.*）に持つ。isConfigured
Core/SSH/SSHConnection.swift      settings + identity + known hosts から SSHClientSettings を組み、connect する 1 か所。ConnectFailure { hostKeyMismatch(expected, actual), other(String) }
Features/Settings/SettingsScreen.swift 設定フォーム。接続テストと、不一致時の「新しい鍵を信用」
Features/Terminal/TerminalScreen.swift 切断理由が hostKeyMismatch なら指紋と「新しい鍵を信用して再接続」を出す
Features/Home/HomeView.swift      歯車 → 設定。未設定なら案内。スパイクへの導線を消す
```

- 自走用の環境変数を整理: `MOBILE_IDE_TERMINAL_AUTORUN` / `MOBILE_IDE_TERMINAL_TYPE` は維持。`MOBILE_IDE_SPIKE_HOST` / `_USER` → `MOBILE_IDE_HOST` / `MOBILE_IDE_PORT` / `MOBILE_IDE_USER`（設定の上書き）。新規 `MOBILE_IDE_CONNECTION_TEST=1`（起動直後に接続テストを実行し `SSH test OK|NG <detail>` を出す）。stdout の目印: `SSH pubkey ...` / `SSH hostkey trusted|ok|mismatch <fingerprint>` / `SSH test ...`。`scripts/console-run.py` の MARKERS に `SSH ` を足す

## 実装計画

### 事前準備 [人間👨‍💻]

- [x] なし（実機の確認は Phase 5 の直前にロック解除と同一 Wi-Fi）

### Phase 1: 鍵ストアと移行 [AI🤖]

- [x] `SSHKeyStore` protocol、`KeychainSSHKeyStore`（`kSecClassGenericPassword`、service `com.d0ne1s.mobileide.ssh`、account `ed25519`、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。保存するのは `rawRepresentation` 32 バイト）、`InMemorySSHKeyStore`
- [x] `SSHIdentity`: `init(store:)` で load → 無ければ UserDefaults の `dev.ssh.ed25519.seed` を読んで save し UserDefaults から削除（移行）→ それも無ければ生成して save。`publicKeyLine`（comment は `mobile-ide`）、`regenerate()`（生成 → save → 差し替え）
- [x] `DevKeyStore` の呼び出し元（`TerminalScreen`）を `SSHIdentity` に置き換える。起動時の `SSH pubkey <line>` 出力を `HomeView` の `.task` に移す
- [x] 検証（シミュレータ、移行経路）: 更新前の公開鍵は `...ICKyqxwuRbwRwSg5hjSyUK3JyDUEsqttqQ7y0sTXFyem`。更新版を install → 起動 → `SSH pubkey` が同じ鍵であること（移行成功）。`plutil -p <plist> | grep dev.ssh` が空であること（旧形式が消えている）。さらに再起動して同じ鍵（Keychain から復元）
- [x] 検証（新規）: `xcrun simctl uninstall booted com.d0ne1s.mobileide` → install → 起動 → 新しい鍵が出る。アンインストールで Keychain も消えることを確認（同じ鍵が出たら Keychain が残っている）

### Phase 2: ホスト鍵の TOFU [AI🤖]

- [x] `HostKeyFingerprint`: `NIOSSHPublicKey` → wire → `SHA256:<base64 no padding>`、OpenSSH 行（`<type> <base64>`）との相互変換
- [x] `KnownHostStore` protocol + UserDefaults 実装（キーは `knownhosts.<host>:<port>`、値は OpenSSH 行）
- [x] `TOFUHostKeyValidator`: `validateHostKey` で store を見て、未登録 → 保存して succeed（`SSH hostkey trusted <fp>`）、一致 → succeed（`SSH hostkey ok <fp>`）、不一致 → `lastMismatch = (expected, actual)` を記録して fail（`SSH hostkey mismatch expected=<fp> actual=<fp>`）。`Sendable` にするため記録は `NIOLockedValueBox` か actor 経由
- [x] `SSHConnection.connect(settings:identity:knownHosts:) async throws(ConnectFailure) -> SSHClient`（typed throws は使わず `throws` + `ConnectFailure` にキャスト）。connect が失敗したら validator の `lastMismatch` を見て `.hostKeyMismatch` に変換
- [x] `PTYSession.start` を `SSHConnection` 経由に差し替え。`State.disconnected` の理由を `ConnectFailure` で持てるようにする（`.hostKeyMismatch` は画面で特別扱い）
- [x] `TerminalScreen`: hostKeyMismatch のとき新旧指紋と「新しい鍵を信用して再接続」（known host を actual で上書きして start）

### Phase 3: 設定画面と片付け [AI🤖]

- [x] `ConnectionSettings`（host / port / user。UserDefaults `connection.*`。`isConfigured = !host.isEmpty && !user.isEmpty`）。`TerminalTarget` は settings から作る（`sessionName` / `workingDirectory` は引き続き固定）
- [x] `SettingsScreen`: Form。「接続先」（TextField ×3、port は数値）、「この端末の鍵」（公開鍵行 + コピー + 「鍵を作り直す」→ `confirmationDialog`「古い鍵での接続はできなくなります。authorized_keys に新しい公開鍵を登録してください」）、「ホスト鍵」（登録済みなら指紋と「忘れる」、未登録なら「初回接続時に記録します」）、「接続テスト」（`SSHConnection.connect` → `executeCommand("echo ok")` → close。結果と所要時間。hostKeyMismatch なら alert に新旧指紋と「新しい鍵を信用」）
- [x] `HomeView`: 歯車ツールバー → `SettingsScreen`。`isConfigured` でなければ List に案内を出し端末行を disabled。スパイクへの導線を消す。`Route` は `.terminal` / `.settings`
- [x] `MOBILE_IDE_CONNECTION_TEST=1` で起動直後に設定画面を開いて接続テストを実行し `SSH test OK|NG` を出す。`MOBILE_IDE_HOST` / `_PORT` / `_USER` で settings を上書き（自走用）
- [x] 削除: `Features/Spike/*`、`Core/SSH/SSHSpikeRunner.swift`、`Core/SSH/DevKeyStore.swift`。`OpenSSHPublicKey.swift` は残す
- [x] `scripts/console-run.py` の MARKERS に `SSH ` を追加。docstring の例を新しい環境変数に直す。VERIFY.md の旧スパイク節（`MOBILE_IDE_SPIKE_*`）を書き換える
- [x] `mise run build` / `mise run device-build` が通る

### Phase 4: シミュレータでの自走検証 [AI🤖]

`PLIST=$(xcrun simctl get_app_container booted com.d0ne1s.mobileide data)/Library/Preferences/com.d0ne1s.mobileide.plist`

- [x] TOFU 初回: known host を消した状態（`plutil -remove` or アンインストール直後）で `MOBILE_IDE_CONNECTION_TEST=1 MOBILE_IDE_HOST=127.0.0.1 MOBILE_IDE_USER=d0ne1s` → `SSH hostkey trusted SHA256:...` → `SSH test OK ok`。指紋が Mac の `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` と一致すること
- [x] TOFU 2 回目: 同じ起動 → `SSH hostkey ok <同じ fp>` → `SSH test OK`
- [x] TOFU 不一致（失敗経路）: `plutil -replace 'knownhosts.127.0.0.1:22' -string 'ssh-ed25519 <アプリ自身の公開鍵の base64>' $PLIST`（形式は正しいが別の鍵）→ 起動 → `SSH hostkey mismatch expected=... actual=...` → `SSH test NG hostKeyMismatch`。スクリーンショットで alert に新旧指紋が出ていること
- [x] 不一致からの復帰は画面操作（「新しい鍵を信用」）なので自走では `plutil -remove` で代替し、再度 `trusted` になることを確認。ボタン経路は実機で人間
- [x] 鍵が Keychain にあること: `plutil -p $PLIST` に `dev.ssh` も 32 バイトの seed も無い（「平文が無いことまで見る」）。`SSH pubkey` は再起動をまたいで同じ
- [x] 端末が引き続き動く: `python3 scripts/console-run.py --env MOBILE_IDE_TERMINAL_AUTORUN=1 --until "TERMINAL resized" --keep` → `python3 scripts/verify-terminal.py` が 6 / 6
- [x] 設定画面のスクリーンショット（`MOBILE_IDE_CONNECTION_TEST=1` で開いた状態）

### Phase 5 前の準備 [人間👨‍💻]

- [x] iPhone のロックを解除して Air と同じ Wi-Fi にいることを確認する

### Phase 5: 実機確認 [AI🤖 + 人間👨‍💻]

- [x] [AI] `mise run device-install` → `SSH pubkey` が更新前（`...IC6eD2xHuBh2enu+akq1HINoRnpzcOxWocESK5bh546p`）と同じ（実機でも移行成功）→ `MOBILE_IDE_CONNECTION_TEST=1 MOBILE_IDE_HOST=tsubasanoMacBook-Air-4.local MOBILE_IDE_USER=d0ne1s` で `hostkey trusted` → `test OK`
- [x] [人間] 歯車 → 設定画面。ホスト名 `tsubasanoMacBook-Air-4.local` とユーザー名 `d0ne1s` を入れる（環境変数の上書きは保存されないため）。ホスト鍵の指紋が Mac の `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` と一致する
- [x] [人間] 「鍵を作り直す」→ 確認 → 新しい公開鍵をコピー → Mac の `~/.ssh/authorized_keys` に足す（AI が Universal Clipboard の `pbpaste` で受け取って追記してもよい）→ 接続テスト OK → 端末も開ける
- [x] [人間] 「ホスト鍵を忘れる」→ 接続テスト → 再び記録される

### Phase 6: 片付けと記録 [AI🤖]

- [x] VERIFY.md: 「SSH スパイク」節を「接続設定と鍵（#4）」に置き換え（authorized_keys 登録手順、TOFU の自走手順、plist の改竄手順、実機の手動項目）。「端末（#3）」節の環境変数名を更新
- [x] plan のチェックとログ
- [x] コミット・push、Issue #4 に結果をコメントして閉じる（`Closes #4` は実機確認後）、ロードマップ #10 のチェック。README の構成図の「ed25519 鍵をアプリ内で生成し…」は現状どおりなので変更不要

### 動作確認 [人間👨‍💻]

- [x] Phase 5 の 3 項目

## ログ

### 試したこと・わかったこと
- 2026-09-04: 旧形式（UserDefaults の seed）→ Keychain の移行は、シミュレータ・実機ともに更新前後で同じ公開鍵が出て成功。plist から seed は消えた
- 2026-09-04: ホスト鍵の検証に失敗しても Citadel の `SSHClient.connect` は返ってこない（アラートは出るが 60 秒以上かかった）。validator の結果を 100ms ごとに監視して不一致なら即座に失敗させ、全体に 20 秒のタイムアウトを付けた。**`withThrowingTaskGroup` では直らない**（キャンセルできない connect の子タスクが終わるまでグループが戻らない）。「最初に終わった操作を採る」ヘルパーにして、負けた connect が後から成功したら閉じる形にした。不一致は起動込み 0.6 秒、存在しないホストは 20.6 秒で失敗する
- 2026-09-04: シミュレータの UserDefaults を外から書き換えるのは不安定。`plutil` で plist を直接編集しても cfprefsd のキャッシュに負け、`simctl spawn booted defaults write` も再インストール後はアプリのコンテナと別の場所に書かれて効かなかった。TOFU の不一致経路は DEBUG 限定の起動オプション `MOBILE_IDE_KNOWNHOST=forget|<行>` でアプリ自身に操作させる形にした
- 2026-09-04: `scripts/console-run.py` が `select` + 行バッファ付き `readline` だったため、2 行が同時に届くと 2 行目を取りこぼしていた（`SSH test NG` が出ていないと誤診し 3 往復した）。生の fd を `os.read` して自分で行に切る形に修正
- 2026-09-04: `verify-terminal.py` 内の再起動に接続先の環境変数を渡していなかった（上書きは保存されない）ため 3 項目が偽 fail。`MOBILE_IDE_HOST` / `_USER` を毎回渡すよう修正して 6 / 6
- 2026-09-04: 実機の手動確認（設定入力・指紋一致・鍵の作り直し → Universal Clipboard の `pbpaste` で受け取って authorized_keys に追記 → 接続 OK・端末が開く・ホスト鍵を忘れて再記録）はユーザーが「問題ない」と報告
- 2026-09-04: TOFU の指紋は Mac の `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`（SHA256:uzqJAAa3...）と一致

### 方針変更
- ホスト鍵の記録操作（forget / 差し替え）を DEBUG 限定の起動オプションとしてアプリに持たせた（plan では plist の外部編集で起こす予定だったが不安定）
- `ConnectFailure` を `PTYSession.State.failed` として持たせ、`disconnected(String)` と分けた（ホスト鍵不一致を端末画面でも特別扱いするため）
