# SwiftTerm で tmux セッションに入る（#3）

## 概要・やりたいこと

PTY チャネルの上に SwiftTerm を載せ、`tmux new-session -A -s mobile-ide -c ~/mobile-ide` に入って端末として使える状態にする。ここまで来れば「iPhone から Air の Claude Code に頼む」がハードコード版で成立する（MVP の最初の「使える」到達点）。

- 端末エミュレータは protocol の裏に隠し、将来 libghostty の iOS ターゲットに差し替えられるようにする（README の構成どおり）
- 画面サイズ変更（回転・キーボード表示）で PTY のリサイズを送る
- tmux 内で Claude Code / Codex を起動して描画崩れがないか見る
- アプリを閉じて開き直しても同じ tmux セッションに戻る（`-A` の挙動）

GitHub Issue: nyshk97/mobile-ide#3。前段の #2（Citadel スパイク）で接続・認証・PTY・リサイズ API は通っている。

## 前提・わかっていること

### 決定事項（/dig-lite）

- **tmux はログインシェルに流し込む**。`withPTY` でシェルを開き、`tmux new-session -A -s mobile-ide -c ~/mobile-ide; exit\n` を書く。detach するとシェルも exit してチャネルが閉じる。PTY 経由の対話シェルは `.zshrc` を読むので PATH 前置きは不要（#1 で実測）
- **キーボードは SwiftTerm 標準の `TerminalAccessory`** をそのまま使う（esc / ctrl / tab / 矢印 / `~ | / -`）。自前バー（Shift+Tab、Ctrl トグル、日本語の確定後送信）は #6
- **接続先の固定値**: セッション `mobile-ide`、作業ディレクトリ `~/mobile-ide`（dogfooding 用。プロジェクト一覧化は #5）
- **SwiftTerm v1.20.0 を `exactVersion` で固定**。ビルドツールプラグイン（`SwiftTermBuildInfoPlugin`）を使うので、`xcodebuild` に `-skipPackagePluginValidation` を付ける（mise のビルドタスク側で）
- **端末エミュレータは自前の `UIViewRepresentable` で包み、protocol の裏に隠す**。SwiftTerm 同梱の SwiftUI ラッパーは非 public
- **PTY は端末ビューの初回レイアウトで cols/rows が決まってから開く**。80x24 で開いてから縮めると tmux が描き直して汚れる
- **切断時は「切断されました」と再接続ボタンだけ**。自動再接続は #7
- **描画は既定の CoreGraphics**。Metal はオプトイン（`setUseMetal`）なので #3 では触らない
- ホスト・ユーザー・鍵はスパイク画面の保存値（`@AppStorage("spike.host")` / `("spike.user")` と `DevKeyStore`）を流用する。#4 で正式な設定に置き換わる

### 調査で確定した事実

- SwiftTerm v1.20.0（2026-08-18）: swift-tools 6.2。Xcode 26.6 は Swift 6.3.3 なので扱える。`xcodebuild -help` に `-skipPackagePluginValidation` あり
- `TerminalView`（iOS, UIKit）の中核 API: `feed(byteArray: ArraySlice<UInt8>)` で出力を流す、`TerminalViewDelegate` の `send(source:data:)` でキー入力、`sizeChanged(source:newCols:newRows:)` でリサイズ通知。他のデリゲートメソッド（`setTerminalTitle` / `hostCurrentDirectoryUpdate` / `scrolled` / `requestOpenLink` / `bell` / `clipboardCopy` / `clipboardRead` / `kittyClipboard*` / `iTermContent` / `rangeChanged`）は空実装でよい
- `TerminalView` は既定で `TerminalAccessory` を `inputAccessoryView` に付ける。`nativeForegroundColor` / `nativeBackgroundColor` / `font` で見た目を変えられる
- Citadel の `withPTY(request, environment:) { inbound, outbound in }` は pty-req → shell 要求の順に送る（exec は組み合わせられない）。クロージャを抜けるとチャネルが閉じるので、**端末の寿命の間クロージャ内で待ち続ける**構造にする。`outbound.write(ByteBuffer)` で入力、`outbound.changeSize(cols:rows:pixelWidth:pixelHeight:)` で WindowChange
- `inbound`（`TTYOutput`）は `AsyncSequence`。シェルが exit すると終了する（#2 で確認）

### プロジェクト側の事実

- #2 の成果: `Core/SSH/DevKeyStore.swift`（鍵）、`Core/SSH/SSHSpikeRunner.swift`（接続の書き方の見本）、`Features/Spike/*`（スパイク画面。#4 で消す）
- 自走検証の型: 環境変数で起動直後に該当画面を開き、`print` で機械可読な行を出し、`scripts/spike-run.py` の要領で `--console` から読む
- Air 側から tmux の状態を見られる: `tmux list-sessions`、`tmux list-clients -t mobile-ide -F '#{client_width}x#{client_height}'`、`tmux send-keys -t mobile-ide '...' Enter`、`tmux detach-client -t mobile-ide`。**端末の入出力・リサイズ・切断を Mac 側から観測・操作できる**ので、タッチ無しで検証が組める

### 設計

```
Features/Terminal/TerminalScreen.swift      SwiftUI 画面。接続中 / 切断のオーバーレイ、再接続ボタン
Features/Terminal/TerminalTarget.swift      固定値（host/user は AppStorage、session/path はハードコード）
Core/Terminal/TerminalSurface.swift         protocol。feed(bytes) / onInput / onResize / currentSize
Core/Terminal/SwiftTermSurface.swift        SwiftTerm 実装。TerminalView を持ち TerminalViewDelegate を実装
Core/Terminal/TerminalSurfaceView.swift     UIViewRepresentable。TerminalSurface の UIView を SwiftUI に載せる
Core/SSH/PTYSession.swift                   @Observable @MainActor。connect → withPTY を Task で保持。state / send / resize / close
```

- `PTYSession.start(cols:rows:)`: `SSHClient.connect` → `Task { try await client.withPTY(request) { inbound, outbound in ... } }`。クロージャ内で `outbound` を self に保持し、`tmux ... ; exit\n` を書き、`for try await` で inbound を surface に流す。ループが終わる（シェル exit）か `close()` が呼ばれると状態を `.disconnected` に。close は `client.close()` でチャネルを落とす
- `TerminalScreen`: surface を生成 → `onResize` の初回で `session.start(cols:rows:)`、以後は `session.resize`。`onInput` → `session.send`。surface.feed は session が MainActor で呼ぶ
- 自走検証用の環境変数 `MOBILE_IDE_TERMINAL_AUTORUN=1` で Home から端末画面を最初から開く。`MOBILE_IDE_TERMINAL_TYPE="<text>"` があれば接続後にその文字列を `send` する（入力経路の確認用）。stdout に `TERMINAL <event> ...` を出す: `size CxR`、`connected`、`disconnected <reason>`

## 実装計画

### 事前準備 [人間👨‍💻]

- [ ] iPhone のロックを解除して Air と同じ Wi-Fi にいることを確認する（Phase 6 の直前でよい）

### Phase 1: SwiftTerm を入れてビルドを通す [AI🤖]

- [x] `.mise.toml` の `build` / `install`(showBuildSettings) / `device-build` / `device-install` の `xcodebuild` に `-skipPackagePluginValidation` を追加
- [x] `project.yml` に `SwiftTerm: { url: https://github.com/migueldeicaza/SwiftTerm, exactVersion: 1.20.0 }` と `dependencies` を追加
- [x] `mise run gen` → `mise run build` と `mise run device-build` が通ることを確認（プラグイン検証で落ちたらフラグの付け忘れを疑う）

### Phase 2: 端末サーフェスの protocol と SwiftTerm 実装 [AI🤖]

- [x] `Core/Terminal/TerminalSurface.swift`: `@MainActor protocol TerminalSurface: AnyObject { var view: UIView; var currentSize: TerminalSize?; var onInput: ((Data) -> Void)?; var onResize: ((TerminalSize) -> Void)?; func feed(_ bytes: ArraySlice<UInt8>) }`
- [x] `Core/Terminal/SwiftTermSurface.swift`: `TerminalView` を生成し `TerminalViewDelegate` を実装。`sizeChanged` → `currentSize` 更新 + `onResize`、`send` → `onInput`。他は空実装。フォントは `.monospacedSystemFont(ofSize: 12)`、色は `.systemBackground` / `.label`（ダークモード追従）。`print("TERMINAL size \(cols)x\(rows)")` を出す
- [x] `Core/Terminal/TerminalSurfaceView.swift`: `UIViewRepresentable`。`makeUIView` で `surface.view` を返すだけ。`dismantleUIView` は何もしない（surface の寿命は画面側が持つ）

### Phase 3: PTYSession [AI🤖]

- [x] `Core/SSH/PTYSession.swift`: `enum State { idle, connecting, running, disconnected(String) }`。`start(target:cols:rows:)`, `send(Data)`, `resize(TerminalSize)`, `close()`
- [x] `start`: `SSHClient.connect`（設定は `SSHSpikeRunner` と同じ。`.acceptAnything()` は #4 まで）→ Task で `withPTY`（term `xterm-256color`、初期 cols/rows は引数、`terminalModes: .init([:])`。ECHO はシェル側の既定に任せる）→ クロージャ内で `outbound` を保持、`tmux new-session -A -s <session> -c <path>; exit\n` を write、inbound を `for try await` で読んで `surface.feed`（MainActor へ hop）→ ループ終了で `.disconnected("shell exited")`
- [x] `send` は保持した `outbound.write`、`resize` は `outbound.changeSize(cols:rows:pixelWidth:0,pixelHeight:0)`。接続前に呼ばれたら無視（初回サイズは start の引数で渡る）
- [x] `close`: `client.close()` → Task をキャンセル → `.disconnected("closed")`。画面を閉じる（`onDisappear`）ときに呼ぶ。**tmux セッション自体は Air 側で生き続ける**（クライアントが切れるだけ）
- [x] stdout に `TERMINAL connected` / `TERMINAL disconnected <reason>` を出す

### Phase 4: 画面と導線 [AI🤖]

- [x] `Features/Terminal/TerminalTarget.swift`: `host` / `user` は `UserDefaults` の `spike.host` / `spike.user`、`sessionName = "mobile-ide"`, `workingDirectory = "~/mobile-ide"`
- [x] `Features/Terminal/TerminalScreen.swift`: `TerminalSurfaceView` を全面に置き、`navigationTitle` はセッション名、`.navigationBarTitleDisplayMode(.inline)`。`onResize` の初回で `session.start`、以後 `session.resize`。`onInput` → `session.send`。state が `.connecting` なら ProgressView のオーバーレイ、`.disconnected` なら理由と「再接続」ボタン（同じ target で `start` し直す）。`onDisappear` で `session.close()`
- [x] 表示直後に `TerminalView` を first responder にしてキーボード（＋標準アクセサリ）を出す
- [x] `HomeView`: プレースホルダを「端末を開く（mobile-ide）」ボタンに置き換え、`TerminalScreen` へ push。ツールバーの「SSH スパイク」は残す。`MOBILE_IDE_TERMINAL_AUTORUN=1` なら最初から `TerminalScreen` を開く
- [x] `MOBILE_IDE_TERMINAL_TYPE` があれば `connected` 後 1 秒待って `send`（自走検証用）

### Phase 5: シミュレータでの自走検証 [AI🤖]

`scripts/spike-run.py` を汎用化して `--env KEY=VALUE`（複数可）と `--until <目印>` を受けるようにし、端末の検証にも使う。Air 側の観測は `ssh localhost 'PATH=/opt/homebrew/bin:$PATH; tmux ...'`。

- [x] 事前: `tmux kill-session -t mobile-ide` で無い状態から始める（`list-sessions` に無いことを確認）
- [x] 起動（`MOBILE_IDE_TERMINAL_AUTORUN=1`）→ stdout に `TERMINAL size CxR` → `TERMINAL connected` が出ること
- [x] Air 側で `tmux list-sessions` に `mobile-ide` が 1 つ、`list-clients -t mobile-ide -F '#{client_width}x#{client_height}'` が **アプリの `size CxR` と一致**すること（初回サイズで PTY を開けている証明）
- [x] 出力経路: Air 側で `tmux send-keys -t mobile-ide 'echo OUTPUT_OK_$(date +%s)' Enter` → `mise run shot` のスクリーンショットにその文字列が写ること
- [x] 入力経路: `MOBILE_IDE_TERMINAL_TYPE='echo INPUT_OK\n'` 付きで起動 → Air 側で `tmux capture-pane -p -t mobile-ide | grep INPUT_OK` が出ること（アプリ → PTY → tmux の経路。SwiftTerm のキー → `send` デリゲートは実機で人間が確認）
- [x] Claude Code の描画: `tmux send-keys -t mobile-ide 'claude' Enter` → 数秒待ってスクリーンショット → 枠線・色・プロンプトが崩れていないことを目視。`tmux send-keys -t mobile-ide C-c C-c` で終了
- [x] 切断: Air 側で `tmux detach-client -t mobile-ide` → stdout に `TERMINAL disconnected shell exited` → スクリーンショットに「切断されました」と再接続ボタン。`tmux list-sessions` に `mobile-ide` が**残っている**こと
- [x] 再接続（`-A`）: アプリを再起動（同じ autorun）→ `connected` → `tmux list-sessions -F '#{session_name} #{session_created}'` の created が切断前と同じ（= 同じセッションに attach した証明）
- [x] リサイズ: 現状シミュレータは回転をコマンドで撃てないので、キーボード表示による縦幅変化を使う。first responder になった後の `size CxR` が接続時より rows が小さく、`list-clients` の値と一致すること

### Phase 6 前の準備 [人間👨‍💻]

- [x] iPhone のロックを解除して Air と同じ Wi-Fi にいることを確認する

### Phase 6: 実機確認 [AI🤖 + 人間👨‍💻]

- [x] [AI] `mise run device-install` → autorun 付きで起動し、`connected` と `list-clients` の一致まで自走で確認
- [ ] [人間] アプリを通常起動して「端末を開く」→ tmux に入る → 標準アクセサリの esc / ctrl / tab / 矢印が効く（`claude` を起動して Esc で中断、矢印で履歴）
- [ ] [人間] 横向きに回転 → tmux のステータスバーが横幅いっぱいに描き直される（リサイズが届いている）
- [ ] [人間] 戻るで画面を閉じ、もう一度開く → 同じ tmux セッションの続きが見える
- [ ] [人間] 気になった描画崩れ・操作感をメモして報告（#6 の入力にする）

### Phase 7: 片付けと記録 [AI🤖]

- [x] `VERIFY.md` に「端末（#3）」の節を追加（autorun の環境変数、Air 側の tmux コマンドでの観測手順、期待する stdout 行）
- [x] plan のチェックとログを更新
- [ ] コミット（`Closes #3` は実機確認が通ってから）・push、Issue #3 に実測結果をコメントして閉じ、ロードマップ #10 のチェック

### 動作確認 [人間👨‍💻]

- [ ] Phase 6 の 4 項目

## ログ

### 試したこと・わかったこと
- 2026-09-04: SwiftTerm 1.20.0 は `Shaders.metal` を含むので Xcode 26 では Metal Toolchain が別途要る（`xcodebuild -downloadComponent MetalToolchain`、688MB）。無いと `cannot execute tool 'metal'` で落ちる
- 2026-09-04: `-sdk iphonesimulator` 指定だと SwiftTerm のビルドツールプラグインのホストツール（`SwiftTermBuildInfoGenerator`）が組まれず `Build input file cannot be found` で落ちる。`-destination 'generic/platform=iOS Simulator'` に変えたら通った（runtime の版ズレ回避にもなる）。mise の build / install を切り替えた
- 2026-09-04: 接続待ち（`.zshrc` 起動で数秒）の間にキーボード表示で 48 → 25 行に変わり、そのリサイズが `connecting` 中で捨てられていた。`PTYSession` が最新サイズを覚えて接続完了時に差分を送る形に修正。画面側も `idle` 以外は常に `resize` を呼ぶ
- 2026-09-04: シェルが exit してサーバー側からチャネルが閉じたあと、Citadel の `withPTY` が close し直して `ChannelError.alreadyClosed` を投げる。「shell exited」に正規化した
- 2026-09-04: `--console` 経由の stdout がパイプだと全バッファになり、`connected` 以降の目印行が届かなかった（画面は正しく切断表示になっていたので、切断検知の不具合と誤診しかけた）。`setvbuf(stdout, nil, _IONBF, 0)` で無バッファにして解消
- 2026-09-04: シミュレータ 6 項目 PASS（Claude Code 描画 / detach → disconnected / セッション残存 / 入力経路 / -A 再 attach / サイズ一致）。実機は `.local` 名で接続し 57x27 でクライアントサイズ一致まで自走で確認

### 方針変更
- 検証ドライバ `scripts/spike-run.py` を `scripts/console-run.py` に改名して汎用化（`--env` / `--until`）。端末の一括検証は `scripts/verify-terminal.py` としてコミット
- 切断ステップの検証で、前のアプリ実体の古い tmux クライアントに detach を撃つ競合があった。`#{client_created}` が起動時刻以降のクライアントを待つようにした（アプリ側の不具合ではなかった）
