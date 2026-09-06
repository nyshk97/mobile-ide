review session: 952e985c-f1e8-42c8-ba58-d30953685e84

## 1回目

````text
プランと関連ファイル（`project.yml`、`.mise.toml`、`VERIFY.md`、`SwiftTermSurface.swift`）を読みました。upstream の API は `gh` がサンドボックスで叩けず未検証なので、その点は指摘に含めます。

## P0
- `Phase 1 > 1` — 実装時に `gh api .../commits/main` を叩き直して**その時点の main HEAD** を pin する手順になっているが、`前提` で API 差分（`@MainActor` 付与・`kittyClipboard*` の既定実装・delegate 削除の範囲）を確認したのは 9fc2d2fc 一点。main は動くので、pin 対象と調査対象がズレて未調査のコミットが入り、ビルドエラーや無関係な退行の切り分けが Phase 2 の実機まで持ち越される / 手戻り確定 / `revision:` には調査済みの 9fc2d2fc をフル SHA で直書きし、「HEAD を取り直す」ではなく「9fc2d2fc が main の祖先であることの確認」に手順を変える（進んでいたら差分を読み直してから上げる）。

## P1
- `Phase 1 > 2` — ビルドが通ったことと「PR #657 のコードが実際に入っていること」が別物なのに、それを確かめる手順がない。SPM のキャッシュや解決結果が古いままでも Debug ビルドは普通に通るので、Phase 2 で症状が再現したときに「修正が効かない」のか「古い SwiftTerm を掴んでいる」のか実機の場で切り分けられない / 実機往復が無駄になる / `mise run gen && mise run build` の後に、生成された `Package.resolved`（`.xcodeproj` 内）の SwiftTerm の `revision` が指定 SHA と一致することと、DerivedData の checkout の `iOSTerminalView.swift` に `maximumNumberOfTouches` / ホイール変換（トークンバケット）の記述があることを確認する 1 ステップを足す。
- `Phase 2 > 3` — マウス追跡 off に戻った後の一本指スクロールバックを「従来通り見える」前提で確認項目にしているが、PR #657 は UIScrollView 側の `panGestureRecognizer.minimumNumberOfTouches = 2` を触る。これが追跡 off で元に戻らない実装だと、Claude Code を抜けた後の素のシェルで一本指スクロールが恒久的に死ぬ（今より悪化する）のに、その場合の扱いがプランにない / 実機セッションが「想定外」で止まる / 実機に行く前に PR #657 のマージ差分を読み、`minimumNumberOfTouches` を戻す経路（`mouseModeChanged` の off 側）があるかを確認して、期待値を「戻る」か「二本指必須になる」かに確定させておく。
- `Phase 2 > 4` — 二本指の合格条件が「壊れていなければ OK」で判定不能。代替画面か素のシェルか、tmux の履歴が動くのか何も起きないのが正解かが決まっていないと、実機で見ても pass/fail を書けない / VERIFY.md への追記も曖昧になる / 素のシェル（非代替画面）で `seq 1 200` 後に二本指 → スクロールバックが動く、Claude Code 内（代替画面）では何も起きない、という 2 ケースに分けて期待値を書く。
- `前提・わかっていること > 6`（API 差分） — `kittyClipboard*` の追加は「既定実装があるので実装不要」で済ませているが、既存の `clipboardCopy` / `clipboardRead`（`SwiftTermSurface` が UIPasteboard に繋いでいる唯一の箇所）がリネーム・置き換えされていた場合、既定実装のせいで**コンパイルが通ったままコピー／ペーストだけ黙って死ぬ**。VERIFY.md にもクリップボードの確認項目が無いので誰も気づかない / 静かな退行 / 差分で `clipboardCopy` / `clipboardRead` が残っていることを確認し、Phase 2 に「端末で選択 → コピー → 他アプリに貼れる」を 1 項目足す。
- `Phase 3 > 2` — 「v1.21 が出たら `exactVersion` に戻す」を README と project.yml のコメントに書くだけでは、リリースを見に行くきっかけが無く main pin が放置される / 一時対応が恒久化する / GitHub issue を 1 本立てて（既存の #9・#12・#13 と同じ運用）、コメントからその番号を参照する。

## P2
- `Phase 1 > 1` — XcodeGen 2.45.4 の `revision:` は SPM の commit pin に落ちるが、pbxproj 上の表現（`XCRemoteSwiftPackageReference` の requirement kind）が変わるので、`mise run gen` 後に pbxproj の該当箇所を一度目視しておくと、次に誰かが `exactVersion` へ戻すときの差分が読みやすい。
- `Phase 2 > 1` — 実機手順の前提（iPhone を USB 接続して信頼済み、Tailscale が Connected、`MOBILE_IDE_HOST` は `tsubasamacbook-air.tail9fb38b.ts.net`）が VERIFY.md「端末 → 実機」にしか無い。プラン側にも 1 行参照を置くと当日の再確認が減る。
- `ログ` — プラン内の「ログ」節と `docs/plans/logs/2026-09-05-2345-…md`（現在空）が二重になっている。どちらに書くかを最初に決めておく。

## Q
- `Phase 2 > 2` — PR #657 を入れても一本指スクロールが期待通りにならなかった場合にどこまでやるか（自前で pan → ホイール（ボタン 64/65）変換を書く / `allowMouseReporting` をユーザー設定で切れるようにする / 1.20.0 に戻して見送り、upstream に issue を立てて待つ）が未定 / 決めないと実機で NG が出た時点でプランが止まり、pin を戻すかどうかの判断も宙に浮く。
- `Phase 2 > 3` — 追跡 off の一本指スクロールバックが「二本指必須」に変わる実装だった場合、それを許容するか（Claude Code 中心の使い方なら実害小）、許容しないなら上の代替案に倒すか / 決めないと、症状を直した代わりに素のシェルの操作感を落とした状態でマージされる。

````

**対応**: P0（Phase 1 > 1）: 「main の先頭を取り直す」をやめ、調査済みの 9fc2d2fc627f… をフル SHA で直書きする手順に変更（main は b5338ba へ進んでいることを確認し前提に書いた）。P1（Phase 1 > 2）: ビルドのステップに「Package.resolved の revision が指定 SHA」「checkout に `maximumNumberOfTouches = 1` がある」の確認を書き足した（ステップの合格条件の書き換え）。P1（Phase 2 > 3）: マージ差分で `disableMousePanGesture()` が `minimumNumberOfTouches = 1` に戻すことを確認し前提に書いた（期待値「戻る」で確定、Q の 2 つ目も消える）。P1（Phase 2 > 4）: 二本指を素のシェル / Claude Code 内の 2 ケースに分けて合否を書いた。P1（前提 > 6）: 9fc2d2fc の delegate に `clipboardCopy` / `clipboardRead` が残っていることを gh api で確認し前提に書いた。「選択→コピー→貼れる」の実機項目の追加は見送り（ループ中は項目を足さない。終了報告に回す）。P1（Phase 3 > 2）: README/コメントだけでなく issue を立てて番号を参照するステップに書き換えた。P2（pbxproj の目視）: 見送り（実装時の細部）。P2（Phase 2 > 1）: VERIFY.md の実機前提への参照を 1 行置いた。P2（ログの二重）: plan 内「ログ」は実装中の記録、`logs/` はレビュー原文、という既存 plan と同じ運用なので変更なし。Q（Phase 2 > 2）: 「直らなければ 1.20.0 に戻して記録し、自前変換や設定化は別 plan」と決めて前提に書いた（根拠: 可逆で、原因の切り分けが先）。Q（Phase 2 > 3）: 前提の確認で「戻る」と確定したので Q ではなくなった。

## 2回目

````text
再読しました。前回の P0/P1 はいずれも前提とステップに反映されています（9fc2d2fc の直書き、解決結果の確認、`disableMousePanGesture()` の確認、二本指の 2 ケース、delegate の存続確認、issue 化）。残りは小粒です。

## P0

## P1
- `Phase 2 > 2`〜`Phase 2 > 5` / `Phase 3 > 1` — 実機の観察結果の行き先がステップ上に無い。前提には「直らなければ 1.20.0 に戻してログに残す」と書いたが、Phase 3 は成功前提の VERIFY.md 追記とコミットだけで、NG 時に何をするかのステップが無い。`Phase 2 > 5` で「結果を記録するだけ」とした二本指の挙動も、記録先が Phase 3 の追記項目に含まれていない / 人間が実機で見た直後に AI が次に何をするかが宙に浮き、観察結果（特に合否にしない側）が消える / Phase 3 の先頭に「実機の結果を plan の『ログ > 試したこと・わかったこと』に転記。一本指スクロールが NG なら project.yml を `exactVersion: 1.20.0` に戻し、VERIFY.md 追記と issue 化は行わずログだけ残して終える」を分岐として置く。

## P2
- `Phase 1 > 1` / `Phase 3 > 2` — project.yml のコメントに書く issue 番号を Phase 1 で要求しているが、issue を立てるのは Phase 3。順序が逆で同じ行を 2 回触ることになる / Phase 3 の issue 作成を Phase 1 の先頭に移すか、Phase 1 ではコメントに PR #657 のリンクだけ書き、番号は Phase 3 で足すと決めておく。
- `Phase 1 > 1` — project.yml の `packages:` 冒頭コメント「Package.resolved は … 再現性は exactVersion で担保する」が SwiftTerm を `revision` に変えると実態と合わなくなる（Citadel は exactVersion のまま）。SwiftTerm 側のコメント追加と一緒に、この共通コメントも「exactVersion か revision で担保」に直す。
- `Phase 1 > 2` — 確認対象の Package.resolved のパス（`MobileIDE.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`）と checkout のパスが書かれていない。加えて、ソース文字列の grep より checkout の `git rev-parse HEAD` が指定 SHA と一致するかの方が確実なので、そちらを主にして grep は補助にする。
- `前提・わかっていること > 16`（参照先の指定） — 9fc2d2fc は main の先頭ではない中間コミットなので、upstream が main を force-push すると解決できなくなる余地がある（可能性は低い）。Phase 3 の issue に PR #657 と マージコミット 5d3026a6 のリンクを併記しておくと復旧の手がかりになる。

## Q

````

**対応**: P0 なしで収束。P1（Phase 3 の NG 分岐）: Phase 3 の先頭に「実機の結果をログに転記。一本指が NG なら 1.20.0 に戻し issue を閉じて終える」を置いた（ステップの追加。未レビュー）。P2（issue 番号の順序）: issue 作成を Phase 1 の先頭に移し、README への番号記載を Phase 3 に残した。P2（packages 冒頭コメント）: 「exactVersion か revision で担保」に直すよう Phase 1 に書いた。P2（Package.resolved のパス・rev-parse）: パスを明記し、`git rev-parse HEAD` を主、grep を補助にした。P2（force-push の余地）: issue に PR #657 とマージコミット 5d3026a6 のリンクを併記するよう書いた。
