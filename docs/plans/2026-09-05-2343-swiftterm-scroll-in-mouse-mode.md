# マウス追跡中の指なぞりが範囲選択になる件（SwiftTerm 1.20.0 に留めて一本指ドラッグをホイールに変える）

## 概要・やりたいこと

実機で Claude Code の画面を一本指でなぞるとスクロールせず、なぞった範囲が文字選択になり「copied 56 chars to tmux buffer」と出る。原因はアプリでも tmux でもなく、SwiftTerm 1.20.0 の iOS 実装が「マウス追跡中の一本指ドラッグをマウスドラッグ（ボタン 1 押下 → 移動 → 離す）としてアプリに送る」ことにある。ホイール（ボタン 64/65）への変換は macOS の `scrollWheel` にしかない。

upstream の PR #657「Bound Apple wheel reports and improve iOS gesture routing」（2026-09-03 マージ）がこの症状そのままの対処。当初は SwiftTerm の参照先を main のコミットに進める計画だったが、main は v2 開発中で `getTerminal()` が消えるなど本アプリに影響する API 変更が多く（ログ > 方針変更）、**1.20.0 に留めたまま `WheelScrollingTerminalView`（`TerminalView` のサブクラス）で #657 と同じ振り分け（マウス追跡中の一本指ドラッグ → ホイール報告、二本指 → 従来のスクロール）を差し込む**方針に変えた。#657 を含むリリースに上げたらサブクラスを消す（#14）。実機で「一本指でスクロールできて選択にならない」ことを確認する。

## 前提・わかっていること

- 症状が出る画面は Claude Code の TUI。Claude Code 自身がマウス追跡を有効にしている（「Jump to bottom (click) ↓」と「copied N chars to tmux buffer · paste with prefix +…」はどちらも Claude Code のメッセージ）。Air の tmux は `mouse off`（`tmux show -g mouse`）で無関係
- SwiftTerm 1.20.0（DerivedData の checkout、`Sources/SwiftTerm/iOS/iOSTerminalView.swift`）の該当箇所:
  - `mouseModeChanged` (3364) がマウス追跡 on で `enableMousePanGesture()` → `panMouseHandler` (1194) を追加する
  - `panMouseHandler` は `.began` で押下、`.changed` で `sendMotion`、`.ended` で離す、を送るだけ。ホイールに変換する分岐は無い
  - `encodeButton` (Terminal.swift:6916) は button 4/5 → 64/65 を持っているが、iOS からは呼ばれていない
- 修正は upstream main にある。v1.20.0（2026-08-18）→ PR #657 マージ（2026-09-03、コミット 5d3026a6）→ main 先頭 9fc2d2fc（2026-09-04）。**v1.20.0 より新しく、まだリリース番号が付いていない**。PR の要旨:
  - 一本指の縦ドラッグはホイール報告（100 回/秒のトークンバケット、初回バースト 6）に変換。`panMouseGesture.maximumNumberOfTouches = 1`、UIScrollView 側の `panGestureRecognizer.minimumNumberOfTouches = 2` にして二本指はローカルのスクロールバックに残す
  - マウス追跡 off で代替画面かつ Alternate Scroll Mode なら一本指をカーソルキーに変換。`allowMouseReporting = false` なら UIKit に返す
  - タップの転送は従来通り（Jump to bottom のクリックは効くはず）
- v1.20.0 → main の API 差分で本アプリに関わるもの:
  - `TerminalViewDelegate` に `@MainActor` が付いた。`SwiftTermSurface` は `@MainActor` なので問題なし
  - `kittyClipboard*` 系 5 メソッドが増えたが、`AppleTerminalView.swift:4819` の `extension TerminalViewDelegate` に既定実装があるので実装不要のはず（ビルドで確定する）
  - 「Drop various delegate methods that were only ever implemented by views」は `Terminal.Delegate`（内部）側で、`TerminalViewDelegate` の既存メソッドは残っている
- 参照先の指定は project.yml の `exactVersion: 1.20.0` → `revision: 9fc2d2fc627f291727e82d5449ec22df76320671`。**API 差分を調べたのはこのコミットなので、実装時に main の先頭を取り直さずこの SHA を直書きする**（main は 2026-09-04 19:37 に b5338ba へ進んでおり、未調査のコミットが入る）。Package.resolved は gitignore なので再現性は project.yml の 1 点で担保する運用は変わらない。**次のリリース（v1.21 など）が出たら `exactVersion` に書き戻す**（Phase 3 で issue 化してきっかけを残す）
- 9fc2d2fc の `TerminalViewDelegate` に `clipboardCopy` / `clipboardRead`（`SwiftTermSurface` が UIPasteboard に繋いでいる箇所）と、本アプリが実装している他の既存メソッドは全て残っている（`gh api` で確認）。コンパイルが通ったままコピーだけ黙って死ぬ経路は無い
- PR #657 の `disableMousePanGesture()` は `panGestureRecognizer.minimumNumberOfTouches = 1` に戻す（マージ差分で確認）。マウス追跡が off に戻れば一本指のスクロールバックは従来通りで、「二本指必須」に変わる恒久的な退行は無い
- ~~実機で PR #657 を入れても一本指スクロールが直らなかった場合は、project.yml を 1.20.0 に戻して観察結果をログに残し、自前の pan → ホイール変換や `allowMouseReporting` の設定化は本 plan ではやらない~~（ログ > 方針変更。サブクラスで自前変換する方針になった）
- 「固定」は「更新しない」ではなく「参照先をタグでなくコミットで指す」の意味（ユーザーと合意済み）
- ジェスチャーはシミュレータの自走では撃てない（`simctl` にジェスチャー注入は無い）。自走で見るのは「上げてもビルド・既存の端末経路・ユニットテストが壊れていないこと」まで。スクロールの本体は実機で手で確認する

## 実装計画

### ~~Phase 1: SwiftTerm を main の revision へ~~ → Phase 1: 1.20.0 のまま `WheelScrollingTerminalView` を差し込む [AI🤖]
- [x] GitHub issue #14 を立てる（当初「exactVersion に戻す」→ 方針変更後「#657 を含むリリースが出たらサブクラスを消す」に書き換えた）
- [x] ~~project.yml の SwiftTerm を `revision: 9fc2d2fc…` にする~~ → 一度変えて依存解決（Package.resolved / checkout の `git rev-parse HEAD` とも 9fc2d2fc）は通ったが、`getTerminal()` が無くビルド不能。`git checkout project.yml` で 1.20.0 に戻した
- [x] `MobileIDE/Core/Terminal/WheelScrollingTerminalView.swift`: `mouseModeChanged` を override して super（ドラッグ選択の pan）を呼ばず、一本指（`maximumNumberOfTouches = 1`）の pan でセル行ごとにホイール（ボタン 4 / 5、1 イベント最大 4 報告）を `getTerminal().sendEvent` で送る。同時に UIScrollView の `panGestureRecognizer.minimumNumberOfTouches` を 2 にし、追跡 off で 1 に戻す。`SwiftTermSurface` が `TerminalView` の代わりにこれを作る
- [x] `MobileIDETests/WheelScrollingTerminalViewTests.swift`（6 件）: 追跡 on/off でのジェスチャー切替、下ドラッグ → `ESC [ < 64 ; col ; row M` × 行数、上ドラッグ → 65、端数の持ち越し、1 イベントの上限、追跡 off では送らない。`mise run test` で 39 件 PASS。override を super 呼びだけ（1.20.0 の挙動）に差し替えると切替のテストが FAIL することを確認
- [x] `form` セッションでの自走（`mobile-ide` は実機の Claude Code が attach 中なので verify-terminal.py は回さない）: `TERMINAL connected form 54x45` → `resized 54x25`、DECCKM on で `^[OA` / off で `^[[A`、Claude Code の描画が崩れていない（`mise run shot`）
- [x] DEBUG の目印行 `TERMINAL mouse on|off`（状態が変わったときだけ）を足し、`form` で Claude Code を起動すると `KEYS done` の後に `TERMINAL mouse on` が出ることを確認。tmux は再描画ごとにモードを送り直すので `mouseModeChanged` は同じ状態でも何度も呼ばれる（install / remove は冪等なので問題なし）

### Phase 2: 実機で確認 [人間👨‍💻]
前提（USB 接続して信頼済み・Tailscale が Connected・接続先 `tsubasamacbook-air.tail9fb38b.ts.net`）は VERIFY.md「端末（#3）→ 実機」の通り。
- [x] `mise run device-install`（BUILD SUCCEEDED / App installed）。`console-run.py --device ... --until "TERMINAL mouse on"` で起動 → `mobile-ide`（Claude Code が動いている）に attach した直後に `TERMINAL mouse on` が出た（実機でホイール経路に入っている証拠）
- [x] Claude Code を起動した画面で一本指で上下になぞる → 会話がスクロールし、選択・「copied N chars」が出ない（2026-09-06 ユーザー確認「スクロールはできる」）
- [x] 「Jump to bottom (click) ↓」をタップすると末尾へ飛ぶ。**キーボードを閉じた状態では 1 回目でフォーカスが入るだけだった**（ユーザー報告）→ `UnfocusedClickGestureRecognizer` を足して再インストール。閉じた状態・開いた状態の両方で飛び、キーボードは出ない（2026-09-06 ユーザー確認 OK）
- [x] ~~Claude Code を抜けた素のシェルで、`seq 1 200` の後に一本指で上になぞる → 従来通りスクロールバックが見える~~ → **前提が誤り**（ログ > 方針変更）。tmux の `mouse on` を `mobile-ide` セッションに手で入れて実機で試し、copy-mode でスクロールできること・タップでキーボードが出ない副作用を含めて「問題なさそう」（2026-09-06 ユーザー確認）。アプリの `launchCommand` に `set-option mouse on` と copy-mode のホイール 1 行を組み込んだ
- [x] ~~二本指は 2 ケースに分けて見る~~ → 合否にしない項目として閉じる（polish-impl 1 回目で決定）。tmux のクライアントは代替画面なので外側に見えるスクロールバックが無く、二本指で見えるものは無い。Claude Code 内の二本指も選択にはならない（一本指と同じ経路で `panMouseGesture` を付けていないため。ジェスチャーは自走で撃てず、ユーザーの実機確認は一本指・タップのみ）

### Phase 3: 記録 [AI🤖]
- [x] 実機の結果を「ログ > 試したこと・わかったこと」に転記した（2026-09-06）。**一本指スクロールが NG なら** `WheelScrollingTerminalView` の差し込みを外して（`SwiftTermSurface` を `TerminalView` に戻す）issue #14 にその旨を書き、以下の追記・コミットは行わずログだけ残して終える
- [x] VERIFY.md「端末」の実機の節に一本指スクロール・Jump to bottom・素のシェルのスクロールバックを追記。シミュレータ節に `mobile-ide` が実機に使われているときの回避と `WheelScrollingTerminalViewTests` を追記
- [x] README の SwiftTerm 記述に「1.20.0 固定。`WheelScrollingTerminalView` で回避、#14 で消す」を書いた
- [ ] コミット（`/commit`）

## ログ
### 試したこと・わかったこと
- 2026-09-06: main（9fc2d2fc）への pin は依存解決まで通った（Package.resolved と checkout の HEAD が一致、`maximumNumberOfTouches = 1` も入っていた）が、`SwiftTermSurface.usesApplicationCursorKeys` の `getTerminal()` が「no member」でビルド不能。main は v1.20.0 から 195 コミット進んだ v2 開発中で、移行ガイド `MigratingFrom1To2.md` は `getTerminal()` の代替をスナップショット API としているが `applicationCursor` は含まれない（delegate コールバックの `source: Terminal` を掴む回り道しか無い）。途中に「serious regressions を持ち込む」と書かれたコミット（da5e9b83）もある
- 「修正前」相当の確認: `mouseModeChanged` の override を `super` 呼びだけにして `mise run test` → `testMouseModeSwitchesOneFingerToWheelAndTwoFingersToScroll` が `XCTAssertTrue failed` / `("1") is not equal to ("2")` で FAIL、他 5 件は `reportWheel` を直接呼ぶので PASS（変換の計算だけを見るテスト）。戻して 39 件 PASS
- `mobile-ide` の tmux セッションには実機の Claude Code（`claude.exe`）が居たので、`mobile-ide` を蹴る verify-terminal.py は回さず `form` で確認した
- 2026-09-06: 「素のシェルだとスクロールできない」の報告。SwiftTerm の `scroll()` はステータス行でスクロール領域が縮んでもスクロールバックに積む（`scrollTop == 0` の分岐）が、**tmux のクライアントは `alternate-screen on` で常に代替画面に描く**ので、外側の SwiftTerm にスクロールバックが無い。今回の変更前から外側ではスクロールできなかった。tmux 側で `mouse on` にすれば tmux がホイールを copy-mode で処理し（`WheelUpPane` → `copy-mode -e`）、マウスを使うアプリには `send-keys -M` で転送する。`mobile-ide` セッションだけ `set -t mobile-ide mouse on`、copy-mode の `WheelUp/DownPane` を `-N 5` → `-N 1`（指 1 行 = 1 行）にして実機で確認 → OK。tmux CLI で bind の中の `;` は `\;` の 2 文字を渡す（`;` そのままだと tmux のコマンド区切り。Claude Code の Bash tool では zsh が `\;` を `;` にするので python の argv で渡した）
- 2026-09-06: 実機で「Jump to bottom」タップ → 入力欄にフォーカスが入るだけ、の報告。1.20.0 の `singleTap` は `isFirstResponder` でなければ `becomeFirstResponder()` するだけでクリックを送らない（iOSTerminalView.swift:1009-1065）。PR #657 も同じ箇所を「追跡中のアプリにはフォーカス無しでも `forwardTap(at:)` で転送し、キーボードは出さない」に直している。サブクラスに `UnfocusedClickGestureRecognizer`（フォーカス無し・追跡中だけ認識、それ以外は `touchesBegan` で即失敗）を常設し、SwiftTerm の 1 回タップに `require(toFail:)` させた。テスト 2 件追加で 41 件 PASS。再インストール後も attach で `TERMINAL mouse on`
- 2026-09-06: polish-impl の指摘で Air の `mode-keys` が **vi** と判明（`EDITOR` に vi が含まれると自動で vi）。実機で試した copy-mode のホイールは `copy-mode` テーブルにしか `-N 1` を入れていなかったので既定の 5 行刻みだった。`copy-mode-vi` にも流すようにしたので、素のシェルの一本指スクロールは指 1 行 = 1 行になる（実機で体感の再確認が要る。速すぎ・遅すぎなら `-N` を調整）
- 2026-09-06: 実機結果（ユーザー確認）: 一本指スクロール OK（「スクロールはできる」）。Jump to bottom はキーボードを閉じた状態・開いた状態とも飛び、キーボードは出ない（OK）。tmux `mouse on` を入れた素のシェルの一本指スクロール・タップでキーボードが出ない副作用ともに「問題なさそう」
- 2026-09-06: `launchCommand` に tmux コマンド列を組み込んだ後の end-to-end: `form` の `mouse` を `set -u` で消してからシミュレータで attach → `TERMINAL connected form` の直後に `TERMINAL mouse on`、`show -t form -v mouse` = on、`show -gv mouse` = off、`list-keys -T copy-mode | grep Wheel` が `-N 1`。attach 直後の画面に tmux のエラーは出ていない（`capture-pane` はプロンプトのみ）
- 2026-09-06: 実機（iPhone Air）に install し、Tailscale 経由で `mobile-ide` に attach → `TERMINAL connected mobile-ide 57x47` → `probe ok` → `TERMINAL mouse on`。一本指スクロールの目視は Phase 2 の残り

### 方針変更
- 2026-09-06: **main の revision への pin を中止し、1.20.0 に留めてサブクラスで #657 相当を差し込む**。理由: main は v2 開発中で `getTerminal()` 削除などアプリに影響する API 変更を多数含み、未検証の変更を丸ごと受け入れることになる。ユーザーに「1.20.0 + 自前」「main に上げる」「止める」を提示し、前者を選択。前提にあった「自前の pan → ホイール変換はこの plan ではやらない」は「#657 が効かなかった場合」の決定だったので、この状況には適用しない。issue #14 は「#657 を含むリリースが出たらサブクラスを消す」に書き換えた
- 2026-09-06: **素のシェルのスクロールは tmux の `mouse on` で実現し、アプリが開くセッションだけに効くよう `launchCommand` の tmux コマンド列に `set-option mouse on` と copy-mode のホイール 1 行を組み込む**。dotfiles の tmux.conf にしなかったのは、アプリが開かないセッション（デスクトップ側だけで使う tmux）まで変えないため。アプリが一度開いたセッションは Mac から attach しても mouse on のまま（セッションオプション）で、これは受け入れる。副作用として tmux が常にマウス追跡するので、素のシェルでもタップでキーボードは出ず、バーの切替で出す（ユーザー了承）。Phase 2 の「素のシェルは従来通りスクロールバック」は前提が誤りだったので取り消し
