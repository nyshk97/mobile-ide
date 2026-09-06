review session: aeb9b010-7d3e-4c4e-8e3b-0eff41411139

## 1回目

````text
レビューしました。plan（`docs/plans/2026-09-06-1131-chat-composer.md`）と実装を突き合わせ、差分と新規ファイルを全部読んでいます。ビルド実行は許可が下りなかったので、コンパイル・自走の再現は plan のログ（12/12、`mise run test` 全通過）を信用して、静的な読みでの指摘です。

## P0

## P1
- `MobileIDE/Features/Terminal/ComposerView.swift:ComposerTextView.maxHeight` — 入力欄が最大 6 行（約 139pt）まで伸びるが、`TerminalScreen.body` の VStack で端末側に下限が無い。横向き（`INFOPLIST_KEY_UISupportedInterfaceOrientations` に landscape が入っている）でキーボードを出すと、可用高 ≈ 350pt − キーボード ≈ 190 − バー 46 − 入力欄 139 で端末の取り分がほぼ 0 になり、数行の下書きを書いた時点で出力が見えなくなる（`changeSize` に極小 rows が飛ぶ）。`maxHeight` を「6 行」と「コンテナ高の 40% 程度」の小さい方に丸めるか、`TerminalSurfaceView` に `frame(minHeight:)` を付けて端末の取り分を先に確保する。
- `MobileIDE/Features/Terminal/TerminalScreen.swift:sendDraft` — `session.send(data)` の直後に無条件で `draft = ""` にしている。`PTYSession.send` は enqueue するだけで失敗を返さず、`state == .running` でも死にかけの接続では書き込みが黙って落ちる。1 キーずつの直接入力なら数文字の損失で済んだが、composer は「長い指示を書く」ための機能なので、日本語 3 行の指示が痕跡なく消える（送信控えは範囲外と決めたので戻す手段も無い）。送信テキストを `lastSent` に退避し、書き込み完了（または一定時間内に `state` が `.running` から外れなかったこと）を確認してから空にする。
- `MobileIDE/Core/Terminal/ComposerStore.swift:ComposerStore` — 型のドキュメントが「下書きの保存は送信時・画面を閉じるとき・バックグラウンドに入るときに呼ぶ（打鍵ごとには書かない）」のままで、実装（`TerminalScreen` の `onChange(of: draft)` で毎回保存）と正反対。しかもここは plan の「方針変更」で、onDisappear 保存だと開き直しの onAppear が先に走って空を読む、と実測して直した箇所。コメントを読んだ次の人が「実装がコメントとズレている」と判断して onDisappear 保存に戻すと、同じバグを踏み直す。コメントを実装（変わるたびに保存・理由）に合わせる。
- `MobileIDE/Core/SSH/PTYSession.swift:resize` — レビュー 1 回目で挙げて「ループ中は見送り、終了報告へ」とした行数変化のデバウンスが未対応のまま。入力欄が 1→2→3 行と伸びるたびに `sizeChanged` → `resize` → `changeSize` が即発火し、改行を打つたびに tmux / Claude Code の TUI が全面再描画される（composer は複数行前提なので毎回踏む）。`resize` に 150〜200ms のデバウンス（最後の値だけ送る）を入れる。

## P2
- `MobileIDE/Features/Terminal/KeyboardBar.swift:KeyboardBar.inputMode` — 既定値が `.direct` だが、アプリの既定モードは `.composer`。渡し忘れたビューは「チャット入力に切り替える」アイコンを出したまま実際は composer、という取り違えになる。既定値を消して必須引数にする（呼び出しは `TerminalScreen` と Preview だけ）。
- `MobileIDE/Features/Terminal/TerminalScreen.swift:sendDraft` — 切断時の通知に `AttachmentFlow.Alert` を借りている。添付と無関係なアラートが `attachments` 経由で出るので、アップロード中に送信を失敗させると添付側のアラートを上書きする。画面に自前の `@State private var alert` を持たせるか、アラートの持ち主を `AttachmentFlow` から画面側に上げる。
- `MobileIDE/Features/Terminal/AttachmentFlow.swift:AttachmentFlow.send` — 冒頭の `guard session.state == .running` が残っているので、composer モードでも再接続中は写真を選んだ時点で弾かれる。アップロードは PTY と別の SSH 接続を張るし、plan の決定は「composer なら接続状態に関係なく入力欄に挿す」なので、この入口ガードだけ意図とズレている。ガードを direct のときだけにする（`deliver` の持ち主に合わせて呼び出し側で判定する）。
- `MobileIDE/Features/Terminal/ComposerView.swift:ComposerController.focus` — `textView` が weak で残っている（モード切替直後の解放前）と、画面から外れた view に `becomeFirstResponder()` して失敗し、`wantsFocus` も立たないのでフォーカスが落ちる。`textView?.window != nil` を条件にして、そうでなければ `wantsFocus = true` に倒す。
- `MobileIDE/Features/Terminal/ComposerView.swift:ComposerController.insert` — 挿入後に `selectedRange` は動かすが `scrollRangeToVisible` を呼ばない。7 行以上の下書きに `@パス ` を挿すとカーソルが表示領域の外に残る。挿入の最後に 1 行足す。
- `MobileIDE/Features/Terminal/TerminalScreen.swift:insertIntoDraft` — direct モードでも `MOBILE_IDE_DRAFT` / `MOBILE_IDE_COMPOSE` が入力欄（= 保存される下書き）に書き込む。DEBUG 限定なので実害は自走の後片付けだけだが、`verify-composer.py` が下書きを毎回 `cat` に流して掃除しているのはこの副作用の裏返し。自走の入口をモードで弾くか、DRAFT/COMPOSE は composer モードのときだけ効くと `LaunchOptions` のドキュメントに書く。
- `scripts/verify-composer.py` — シナリオ 1 が `COMPOSE sent bytes=24` を直値で見ている。包み方を変えたら中身が正しくても FAIL する。`bytes=` の値を `len(start+body+end)+1` から計算するか、目印行の有無だけ見る。

## Q
- `MobileIDE/Features/Terminal/ComposerView.swift:ComposerTextView` — 横向きを端末画面のサポート範囲に残すか。残すなら上の P1（端末の最小高さ / 入力欄の上限）を実装が要り、落とすなら `TerminalScreen` を portrait 固定にするだけで済む。決めないと、実機の横向きで入力欄を伸ばしたときに端末が見えなくなる形が残る。
- `MobileIDE/Features/Terminal/TerminalScreen.swift:sendDraft` — 送信直後に接続が落ちて本文が消えたときの救済を今回の範囲に入れるか（下書きに戻す / 直前の送信本文を 1 件だけ保持する）。plan では「送信履歴は範囲外」と決めているが、失敗時の復帰はそこで判断していない。決めないと P1 の直し方（`lastSent` を持つか、単に送信成功まで空にしないか）が定まらない。

````

**対応**: P0 なしで収束。P1: `ComposerStore` のドキュメントを実装（変わるたびに保存・理由）に合わせた。入力欄の上限 / 端末の最小高さ（横向き）、送信控え（`lastSent`）、`resize` のデバウンスは仕組みの追加なのでループ中は見送り、終了報告へ。P2: `KeyboardBar.inputMode` の既定値を消して必須に / `AttachmentFlow.send` 冒頭の running ガードを削り、direct モードのときだけ `TerminalScreen.attach` で判定（composer は切断中でも入力欄に挿せる）/ `ComposerController.focus` は `textView.window != nil` を条件に、外れていれば `wantsFocus` / `insert` の末尾に `scrollRangeToVisible` / DRAFT・COMPOSE は composer モードで使うと LaunchOptions のドキュメントに追記 / verify-composer.py の `bytes=24` を包みの長さから導出。切断時アラートの持ち主を画面側に上げる件は仕組みの変更なので見送り（終了報告へ）。Q はどちらもこちらで決定: 横向きは対象に残す（README の実機確認に横向きがある。入力欄の上限は別件）/ 送信直後の接続断の救済は今回の範囲外（`PTYSession.send` が結果を返さない作りで、変えるなら別件）。plan の決定事項に追記。
