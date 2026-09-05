review session: 9730eef9-1919-41c6-ac35-cc0c5a7a5193

## 1回目

````text
plan と現物（VERIFY.md / CLAUDE.md / docs/tailscale.md / 既存 issue・plan / 実機の `claude --help`・mise の配置）を突き合わせました。

## P0
- `Phase 0 > 2` — #9 のタイトルを「段階 8: ホストのセットアップを…」に変えるとしているが、#8 は画像添付で `docs/plans/2026-09-05-1807-image-upload.md` が未コミットのまま進行中（本文にも「Issue #8」「ロードマップ #10 のチェック」）。同じ「段階 8」が 2 つになり、#10 のロードマップ行と plan ファイルの対応が崩れて後で番号を振り直す羽目になる / 段階番号は据え置き（#9 =「段階 9: ホストのセットアップをスクリプト化して Air で通す」）にし、切り出す mini 側を次の段階番号にする。Phase 0 の最初に #10 の現行ロードマップを読んで採番を確定してから 3 つの issue 操作を流す。
- `設計 > 5`, `設計 > 6` — Brewfile は `~/Library/CloudStorage/Dropbox/Brewfile`、Claude Code CLI は mise の node 24.13.0 配下、`~/.zshrc` も Dropbox 実体の symlink（今回確認済み）。つまりスクリプトは「Dropbox がインストール済み・サインイン済み・同期済み」「Homebrew と mise と node が入っている」を暗黙の前提にしているのに、その Dropbox も Homebrew も Brewfile 由来という循環になっている / 素の mini で「同じスクリプトを流すだけ」という本 issue の目的がそのままでは成立せず、到着後にブートストラップ手順を書き足す手戻りが確定する / ステップ 0 として前提チェック（`brew` / `mise` / Brewfile パス / `~/.zshrc` が解決できるか）を入れ、欠けていたら「人間が先にやること」を列挙して即終了させる。Brewfile パスは `--brewfile` で上書きできるようにし、mini の順序（Dropbox → dotfiles → 本スクリプト）を docs/tailscale.md か VERIFY.md に明記する。
- `設計 > 2` — `systemsetup -setremotelogin on` は呼び出しプロセスにフルディスクアクセスが要る（Terminal.app に FDA が無いと失敗する）。plan では FDA は「ステップ 7 で最後に列挙」扱いで、事前準備にも入っていない / `set -euo pipefail` なのでここで落ちると、sshd の conf だけ書き換わった中途半端な状態で止まり、mini でも同じ所で毎回止まる / 現状読み取り（`systemsetup -getremotelogin`）→ 既に on なら触らない、off で set に失敗したら abort せず「System Settings → 一般 → 共有 → リモートログイン を手で ON、または Terminal.app に FDA を付与」と出して続行し、最後の未完了リストに積む。事前準備に「Terminal.app に FDA」を人間タスクとして足す。

## P1
- `設計 > 1` — conf を tee したあとの検証が無い。VERIFY.md の printf 版と実体が既にずれていた（`ClientAliveInterval` の 2 行が入っていない）という事実は、書いたつもりが効いていない事故が実際に起きていることを示している / macOS の sshd は接続ごとに launchd が起動するので、壊れた conf を置くと以後の新規接続が全部失敗する。ホストは外出先からの唯一の入口なので締め出されると回復手段が無い / 書く前に既存ファイルを退避 → 書いたら `sudo sshd -t`（構文チェック）→ NG なら退避から戻して非ゼロ終了、という順にする。ついでに `sshd -T` の実効値もスクリプト自身で読んで 1 行出す（Phase 2 の確認と同じもの）。
- `設計 > 7` — GUI 項目を「列挙して終わる」だけなので、mini で漏れても気づけない / FDA の有無は CLAUDE.md / VERIFY.md にある手口（別ソケットの tmux から `~/.config/mise/config.toml` を読ませる、`ssh -o BatchMode=yes localhost` が通るか、`Tailscale status --json` の `Self.DNSName` が取れるか）で自動判定できる。列挙だけだと「やった気になる」チェックリストになる / 判定できるものは `ok` / `未設定` を出し、判定できないもの（Key expiry の無効化など）だけを手作業リストに残す。
- `Phase 1 > 2` — `--dry-run` を「sudo なしで全ステップの分岐を通す」としているが、現状読み取り自体に権限が要るステップがある（リモートログインの状態、`sysadminctl -autologin status`）/ dry-run の出力が「差分あり/なし」ではなく空振りになり、Air での事前確認が検証にならない / 読めなかった項目は `unknown` として出す仕様を設計に書き、期待出力（Air 現状: sshd=差分あり, remotelogin=on, brew=実行, claude-cli=skip）に `unknown` の行も含めて書いておく。
- `Phase 1 の実行 > 2` — 「全ステップが『変更なし』で終わる」の判定基準が無い。`brew bundle` は毎回 `Using ...` を出すし sudo のパスワードも聞かれるので、文字どおりの no-op にはならない / 冪等性の合否が人の主観になり、mini で「本当に流すだけ」かどうかの根拠が残らない / 各ステップが `step=<名前> result=changed|unchanged|skipped` の 1 行を必ず出す形にし、「2 回目は changed が 0 件」を判定基準として VERIFY.md に書く。
- `Phase 2 > 3` — `kill -STOP` した接続が 45 秒で `tmux list-clients` から消えることの確認だが、#7 でアプリは自動再接続するので新しいクライアントがすぐ現れる / VERIFY.md（再接続 → 自走検証の 3 つ目）に既に「古いクライアントを掴んで偽 fail / 偽 pass になる」実例がある。同じ罠を踏む / STOP する前に対象の `sshd-session` の PID と `#{client_created}` を控え、その特定のクライアントだけが消えることを見る。終わったら STOP したままの sshd を `kill -9` で片付ける手順も書く（VERIFY.md 実機の節と同じ）。
- `Phase 2`（ステップ追加） — Air の sshd に `ClientAliveInterval 15` が新しく入るのに、#7 の自走検証を回し直すステップが無い / `scripts/verify-reconnect.py` のシナリオ 2・3 は「凍結中は古い tmux クライアントが残っている」ことを前提に `-D` の効きを判定しており、サーバー側が接続を刈るようになるとこの前提が変わる。壊れていても気づくのは次の段階になる / Phase 2 に `python3 scripts/verify-reconnect.py`（8/8）と `scripts/verify-terminal.py`（6/6）の再実行を足し、結果を VERIFY.md に「ClientAlive を入れた後も通る」と記録する。
- `Phase 4 > 2` — 「直近の `<uuid>.jsonl` を特定」とあるが、`~/.claude/projects/-Users-d0ne1s-mobile-ide/` には AI 自身の作業セッションの jsonl が同時に増え続けるうえ `memory/` ディレクトリも同居している / mtime 最新で拾うと自分の会話を掴んで、Phase 4 の確認そのものが無意味になる / 人間が打つ目印（例「README の 1 行目を読んで」）で `grep -l` して特定する手順にし、ステップ 1 の目印文字列を先に決めて plan に書いておく。
- `事前準備` — 人間側の前提が「iPhone に Claude アプリ」1 行だけ / sudo パスワード、Terminal.app の FDA、Brewfile が Dropbox 同期済みであること、iPhone の Tailscale が Connected であること、が揃っていないと Phase 1 の実行が途中で止まる / 事前準備を上記まで広げ、Phase 1 の実行の直前に置く。

## P2
- `設計` > VERIFY.md の行 — 「手順の printf は残さない」とあるが、現行 VERIFY.md にはその周辺に「なぜ `ClientAliveInterval` が要るか（既定 0 だと数時間残る）」「なぜ `00-` で置くか（先に読まれた値が勝つ）」という理由が書かれている。コマンドと一緒に消えると、スクリプトの中身を読まないと理由が分からなくなる。理由の段落は VERIFY.md に残すか、スクリプト冒頭のコメントに移す。
- `Phase 1 > 4` — docs/tailscale.md「Mac mini 到着後」の書き換えと、Phase 0 で作る mini 用 issue の内容が二重管理になる。tailscale.md 側は「手順は scripts/host-setup.sh と新 issue を見る」に寄せて、実体を 1 箇所にする。
- `設計` — mini では 7 ステップのうち一部だけ流し直したい場面が出やすい（brew bundle だけ、sshd だけ）。`--only <step>` か `--skip-brew` があると到着後が楽になる。今回無くても困らない。

## Q
- `設計 > 4` — mini で FileVault を有効にするかが未決。有効だと `sysadminctl -autologin` は効かず、再起動後に人が触るまで sshd も tmux も上がらない（Air は FileVault オフ）。決めないと「電源断からの無人復帰」をスクリプトで担保できるかが確定せず、ステップ 3・4 の意味が変わる。
- `設計 > 5`, `設計 > 6` — host-setup.sh の守備範囲を「Dropbox / Homebrew / mise / dotfiles は同期済みという前提の続きから」にするか、そこまで含めた素の mini 用ブートストラップにするか。決めないと P0 で挙げた前提チェックを「即終了」にするか「自前でインストール」にするかが決まらず、mini 到着後の作業量の見積もりも出せない。

````

**対応**: P0-1 は #8 = 段階 7（画像添付）なので「段階 8 が 2 つ」にはならないが、採番を #10 を読んで確定するステップと「#9 は段階 8 のまま・新 issue = 段階 9・image-upload の plan には触らない」を決定事項に明記した / P0-2 は Q-2 と合わせて「Dropbox・Homebrew・mise・dotfiles 同期済みの続きから」と決定（根拠: 素の Mac の土台は settings/setup-dotfiles.sh と Brewfile の既存運用）。ステップ 0 の前提チェック（欠けたら列挙して非ゼロ終了）・`--brewfile`・順序の明記を設計に反映 / P0-3 は現状読み → off のときだけ set、失敗しても続行して未完了リストへ、事前準備に Terminal.app の FDA を追加 / P1: sshd の退避 → sshd -t → 戻す（設計 1）、GUI 項目の自動判定（設計 7）、dry-run の unknown と期待出力（Phase 1 > 2）、`result=changed|unchanged|skipped|unknown` と「2 回目は changed 0 件」（Phase 1 の実行）、特定クライアントで見る + STOP の後片付け（Phase 2 > 3）、目印文字列を決めて grep -l で特定（Phase 4）、事前準備の拡充、をすべて反映 / P1「verify-reconnect.py / verify-terminal.py の再実行」はステップ追加なのでループ中は見送り、終了報告に回す / P2: 理由の段落を VERIFY.md に残しスクリプト冒頭にも書く、tailscale.md は新 issue に寄せる、を反映。`--only` は見送り（今回無くても困らない） / Q-1 FileVault は #9 の元の本文どおりオフに決定。

## 2回目

````text
再読しました。前回の P0/P1 は反映されています（採番の決定、守備範囲の確定とステップ 0、リモートログインの非 abort 化、退避 → `sshd -t` → 戻す、result 語彙と「changed 0 件」、特定クライアントでの判定、grep での特定、事前準備の拡充）。以下は残り・今回の修正で新しく出たものです。

## P0
- `設計 > 5`（+ `Phase 1 の実行 > 2`） — ステップ 5 が `brew bundle --file=<Brewfile>` を無条件に流す形のままで、「現状を読む → 違うときだけ書く」になっていない / 冪等性の判定基準が「2 回目は `result=changed` が 0 件」になったので、brew が毎回 `changed` を出すと 2 回目は必ず不合格になり、判定基準かステップ実装のどちらかを後から書き直すことになる / `brew bundle check --file=<Brewfile>` が satisfied なら `unchanged` で即返し、満たしていないときだけ `brew bundle` を流して `changed`。`Phase 1 > 2` の期待出力の `brew=changed（実行する）` も「Air の現状では satisfied なので unchanged が出るはず」なのかを確認して書き直す（Brewfile は既に全部入っているはずなので、期待値自体がずれている可能性が高い）。
- `Phase 4 > 1`, `Phase 4 > 2` — 目印を「合言葉はポレポレ、と覚えて」と plan 本文に書いてしまったため、この plan を読んだ AI セッションの jsonl（今この瞬間のものを含む）に同じ文字列が入る / `grep -l 'ポレポレ' ~/.claude/projects/-Users-d0ne1s-mobile-ide/*.jsonl` は確実に複数ヒットし、「mtime 最新は使わない」で避けたはずの誤検出が別経路で戻ってくる / 目印は plan に書かず、Phase 4 の直前にその場で作る（`openssl rand -hex 3` の値を人間が打つ）。plan には「実行時に生成した 6 桁の hex を目印にする」とだけ書き、絞り込みも「その値を含み、かつ Phase 4 開始時刻以降に更新された jsonl」の 2 条件にする。

## P1
- `設計 > 1` — 「目的の内容で置く」としか書かれておらず、置くべき 4 行が plan のどこにも無い。VERIFY.md の printf は消す方針なので、実装時の唯一の正解が消える / 実体は今 2 行しか無い（記述と実体がずれていた事故の再発経路そのもの）/ 設計に `PasswordAuthentication no` / `KbdInteractiveAuthentication no` / `ClientAliveInterval 15` / `ClientAliveCountMax 3` の 4 行を明記する。`sshd -t` は root が要るので `sudo sshd -t` である点も添える。
- `設計 > 7` — FDA の判定を「sshd 経由で dotfiles が読める」で行うが、これは `ssh -o BatchMode=yes localhost` が通ることが前提で、鍵やリモートログインの都合で落ちたときも「FDA 未設定」に見える / 未設定でないものを未設定と報告すると、mini で存在しない問題を追うことになる / 2 段にする（1: `ssh -o BatchMode=yes localhost true` が通るか → 通らなければ `unknown` と理由 / 2: 通ったうえで `ssh localhost 'cat ~/.config/mise/config.toml'` が `Operation not permitted` にならないか）。CLAUDE.md にある「sshd は読めても tmux サーバーは読めない」も別物なので、判定名を「リモートユーザーの FDA」と明示する。
- `設計 > 7` — 「authorized_keys にアプリの鍵がある」の判定条件が未定義。アプリの鍵はシミュレータ・実機・作り直しで変わるうえ、実体は Dropbox の dotfiles 側 / 「どの鍵があれば ok か」が決まらないと実装できず、判定が常に 未設定 か常に ok のどちらかに倒れる / VERIFY.md にあるとおり公開鍵のコメントが `mobile-ide` なので、`~/.ssh/authorized_keys` に ` mobile-ide` で終わる行が 1 行以上あるか、を条件にする（件数も出すと実機とシミュレータの取り違えに気づける）。
- `Phase 2 > 3` — 「対象の sshd-session の PID」を控えるとあるが、選び方が書かれていない。Mac 側の作業セッションや AI のセッションも同じ `sshd-session: d0ne1s@ttys` で並ぶ / 別の接続を STOP すると自分の作業が固まるか、無関係な接続で 45 秒を待つことになる / iPhone の接続は `netstat -an -p tcp` の接続元が `100.119.208.94` のものと決まっているので、そこから tty → PID を引く手順を書く（VERIFY.md の再接続・実機の節と同じ道具立て）。
- `Phase 0 > 2`, `設計 > docs/tailscale.md` — 手順の実体を新 issue に寄せる形になったが、issue は mini 到着後に閉じられる / 3 台目や再セットアップのときに参照先が閉じた issue の中になり、`docs/` を読んでも順序が分からない / 実体は `docs/` 側（tailscale.md の「Mac mini 到着後」か新設の `docs/host.md`）に置き、新 issue は「docs のこの節をなぞる」チェックリストにする。二重管理を避ける方向は変えない。
- `Phase 1 > 2` — dry-run を `--skip-power --skip-autologin` 付きでしか流さないので、ステップ 3・4 の判定ロジックが一度も実行されない / この 2 つは mini 到着後に初めて動くことになり、「mini では流すだけ」の当日にデバッグする羽目になる / dry-run は書き込みをしないので、フラグ無しでも 1 回流して `power=` / `autologin=` の行（sudo 無しなら `unknown`）が出ることまで見る。期待出力にステップ 0〜7 の全行を並べる。
- `設計 > 6` — 「入っていれば skip」と書いてあるが、`result` の語彙では `skipped` は `--skip-*` で飛ばしたものを指す（`Phase 1 > 2` の期待値は `claude-cli=unchanged`）/ 語彙が混ざると「2 回目は changed 0 件」の集計と、未完了リストの意味が読み手ごとに変わる / 「既にある = `unchanged`」「フラグで飛ばした = `skipped`」と設計に定義を 1 行足す。

## P2
- `事前準備 > 3` — 「Terminal.app にフルディスクアクセス」と固有名になっている。普段使いが別のターミナルなら、FDA を付ける先はそちら。「Phase 1 の実行に使うターミナル.app」と書くほうが安全。
- `Phase 3 > 1` — `claude --remote-control mobile-ide-rc` をアプリが attach 中の `mobile-ide` セッションで起動すると、Phase 4 の会話ログと同じプロジェクトディレクトリに混ざる。Remote Control 用は別セッション（`-rc` 等）で起動すると、Phase 4 の jsonl 特定が楽になる。

## Q
- `設計 > 3`, `設計 > 4` — Air で pmset と自動ログインを一度実際に当てて（確認後に戻して）検証するか、未実行のまま mini に持ち込むかが未決。pmset は戻すのが容易だが、自動ログインは一時的にでも Air のログインを無人化することになる / 決めないと 8 ステップ中 2 つが実機で一度も走らないまま「mini では流すだけ」と宣言することになり、到着当日の手戻りをどこまで許容するかが定まらない。

````

**対応**: P0-1 は brew bundle check → satisfied なら unchanged に変え、Air で check が satisfied なことを実測して期待値を brew=unchanged に直した / P0-2 は目印を実行時に `openssl rand -hex 3` で生成し plan に書かない、絞り込みは「目印を含む」かつ「開始時刻以降に更新」の 2 条件、に変えた / P1: sshd の 4 行と `sudo sshd -t` を設計に明記、FDA 判定を 2 段（ssh が通らなければ unknown）に、authorized_keys は末尾 ` mobile-ide` の行数（Air で 1 件を実測）、Phase 2 > 3 は netstat の接続元 100.x → tty → PID で選ぶ手順に、docs/tailscale.md に手順の実体を置いて issue はチェックリストに、dry-run はフラグ無しで全ステップの行を見る（期待出力にステップ 0〜7 を列挙）、`skipped` と `unchanged` の語彙を定義、をすべて反映 / P2: 「Terminal.app」を「Phase 1 の実行に使うターミナルアプリ」に、Remote Control は別 tmux セッションで起動、を反映 / Q（Air で pmset・自動ログインを実際に当てるか）は /dig-lite の「フラグで飛ばす」どおり当てないと決定し、判定ロジックはフラグ無しの dry-run で通す、mini 当日の手戻りは許容、と決定事項に書いた。

## 3回目

````text
再読しました。前回の P0/P1/P2 と Q は反映されています。今回は 1 件、検証手順の前提そのものが崩れている箇所があります。

## P0
- `Phase 2 > 3` — `kill -STOP` で `ClientAliveInterval` の効きを確かめる設計になっているが、keepalive を送るのは sshd-session プロセス自身なので、そのプロセスを STOP すると keepalive のタイマーごと止まる。凍結された sshd-session は設定値に関係なく自分では終われない / 45 秒待ってもクライアントは消えず、「設定が効いていない」と誤判定して conf・スクリプト・VERIFY.md を書き直す手戻りが確定する。しかも #7 で「数時間残っていた」のは `ClientAliveInterval 0` のせいではなく STOP されたプロセスだったから、という説明のほうが筋が通るので、事実欄（`調査で確定した事実` の #7 に関する行）も同時に誤りを引き継いでいる / 刺激をサーバー側の凍結からクライアント側の無言の消失に変える。自走したいなら `scripts/ssh-proxy.py` の SIGUSR1（ソケットを保ったまま中継を止める＝サーバーから見て応答が返らない）を使い、45 秒で該当クライアントが消えることを見る。実機で見るなら iPhone を機内モードにして 45 秒放置（再接続もできないので新クライアントが混ざらない）。後者にする場合はこのステップを [人間👨‍💻] に移す。`kill -STOP` は #7 どおり「アプリ側の生存判定」の刺激として別に残す。

## P1
- `設計 > 1` — 書いたあと `sudo sshd -T` の実効値を「1 行出す」だけで、期待値との一致を確認していない / この issue の出発点が「printf は 4 行なのに実体は 2 行だった＝書いたつもりが効いていない」なので、出力するだけでは同じ種類のズレを再び見逃す。Air は Phase 2 で人が見るが、mini ではスクリプトの出力が唯一の担保になる / `clientaliveinterval 15` / `clientalivecountmax 3` / `passwordauthentication no` / `kbdinteractiveauthentication no` の 4 つを実効値で突き合わせ、一致しなければ `result` を changed で終わらせずに未完了リストへ積む（Include 順で負けているケースはここでしか捕まらない）。
- `Phase 3 > 1` — 「別の tmux セッションで起動して Phase 4 の会話ログと混ざらないようにする」とあるが、jsonl の置き場を決めるのは tmux セッション名ではなく cwd。同じ `~/mobile-ide` で起動すれば同じ `~/.claude/projects/-Users-d0ne1s-mobile-ide/` に落ちる / 理由づけが事実と違うまま残ると、後で Phase 4 の絞り込み（目印＋時刻の 2 条件）を「もう要らない」と誤って外す判断につながる / 理由を「tmux 上の操作が混ざらないため」に直すか、rc セッションの cwd を `~` など別ディレクトリにして本当にログを分ける。どちらにするか設計に 1 行で書く。

## P2
- `Phase 1 > 2`, `Phase 1 の実行 > 1` — dry-run はフラグ無し、実行はフラグ 2 つ、と打ち分けが必要で、取り違えると Air に `pmset -a sleep 0`（ノートで電池が減り続ける）と自動ログインが当たる。ノート型（`pmset -g batt` にバッテリーがある）を検出したら power / autologin を既定で skip し、当てたいときだけ `--force-power` を要求する形にすると事故が起きない。今回は手順どおり打てば済む。
- `設計 > 1` — 書く前に一度 `sudo sshd -t` を通してベースラインを取っておくと、元から別の drop-in が壊れていた場合に「自分の変更を戻しても直らない」ことをその場で切り分けられる。

## Q

````

**対応**: P0 は指摘どおり `kill -STOP` では keepalive のタイマーごと止まるので、刺激をシミュレータ＋ `scripts/ssh-proxy.py` の SIGUSR1（ソケットを保ったまま中継停止）に変え、事実欄に機序を書き、#7 の「数時間残っていた」を STOP した接続のことと訂正した。あわせて「修正前（2 行の conf）で FAIL することを見る」ステップを足した（CLAUDE.md の動作確認ルール。conf の差し替えは sudo なのでユーザー依頼） / P1: sshd -T の実効値 4 つの突き合わせと不一致時は未完了リストへ、を設計に反映。Phase 3 の理由を「tmux 上の操作が混ざらないため」に直し、jsonl は cwd で決まる旨と Phase 4 の 2 条件で拾える旨を書いた / P2: ベースラインの `sudo sshd -t` を設計に反映。ノート型検出で power / autologin を既定 skip にする案は仕組みの追加なので見送り、終了報告に回す。

## 4回目

````text
再読しました。前回の P0（`kill -STOP` では keepalive のタイマーごと止まる）と P1・P2 は反映されています。差し替え後の刺激に、同じ構図の穴が 1 つ残っています。

## P0
- `Phase 2 > 3`, `Phase 2 > 4` — 刺激を proxy の SIGUSR1 に変えたのは正しいが、判定対象が「アプリが張った tmux クライアント」のままになっている。アプリは凍結を検知して再接続し、その attach は `tmux new-session -A -D`（VERIFY.md 再接続の節・`verify-reconnect.py` シナリオ 3 の「再接続後に 1 件になれば `-D` が効いている証明」）なので、古いクライアントは `ClientAliveInterval` ではなく `-D` に蹴られて数秒で消える / 45 秒待つ前に消えるので 4 行の conf でも 2 行の conf でも同じ結果になり、ステップ 4 の「修正前は残る」ネガティブコントロールが期待どおりに FAIL しない。そこで初めて気づいて刺激と判定をもう一度作り直すことになる（今回と同じ手戻り） / アプリを刺激の当事者から外す。Mac 側から proxy 経由で素の ssh を張って tmux に attach し（`( TERM=xterm-256color script -q /dev/null ssh -p 2222 localhost -t 'tmux attach -t verify' ) &` の形。VERIFY.md 再接続・実機の `-D` 確認と同じ手口）、そのクライアントを凍結する。素の ssh は再接続しないので `-D` が絡まず、45 秒で消える／2 行なら残り続ける、がそのまま設定の効きの証明になる。あわせて判定を二重にする（`tmux list-clients` の該当行と、その接続の `sshd-session` の PID が `ps -p` から消えること）。sshd-session 側は `-D` で detach されても生き残るので、どちらの経路で消えたのかを区別できる。

## P1
- `設計 > 7` — Tailscale の判定を `Tailscale status --json` と書いているが、docs/tailscale.md には CLI の実体が `/Applications/Tailscale.app/Contents/MacOS/Tailscale` と記録されている。スクリプトは非対話 bash で動くので、`~/.zshrc` の alias / function や対話シェル前提の PATH には頼れない / 実体を解決できないと `tailscale=未設定` の誤判定になり、mini 到着日に「入れたはずなのに未設定と出る」で時間を溶かす / `Tailscale` が PATH 上の実体かを実際に確認し、そうでなければ絶対パス（無ければ `/Applications/Tailscale.app/Contents/MacOS/Tailscale` にフォールバック、それも無ければ `未設定`）で呼ぶ。`Phase 1 > 2` の期待値 `tailscale=ok` はこの解決込みで見る。
- `Phase 2 > 4` — 2 行に戻したあと 4 行へ戻す作業を手（ユーザーの Terminal で conf 差し替え）に任せている / 戻し忘れると Air が無防備な状態のまま次のフェーズへ進み、しかも Phase 2 > 1 の `sshd -T` は既に通過済みなので誰も気づかない / 戻しは `bash scripts/host-setup.sh --skip-power --skip-autologin` を流す形にする（ユーザーに頼むのは 2 行に戻す方だけ）。`sshd=changed` が 1 件出て戻ることを確認すれば、「差分あり → 書く」の経路と実効値の突き合わせをもう一度通したことにもなる。

## P2

## Q

````

**対応**: P0 は刺激の当事者をアプリから「proxy 経由の素の ssh で tmux attach」に変え、判定を `tmux list-clients` の該当行と sshd-session の PID の両方が消えることに二重化した。事実欄に「アプリのクライアントは `-D` で蹴られるので刺激に使えない」を追記 / P1: Tailscale CLI は `/usr/local/bin/Tailscale` に symlink があることを実測し、PATH → アプリ内の絶対パスの順で解決する旨を設計に書いた。2 行に戻した後の復旧は `host-setup.sh` を流して `sshd=changed` 1 件で確認する形に変えた（ユーザーに頼むのは 2 行に戻す方だけ）。

## 5回目

````text
再読しました。前回の P0（`-D` による偽 pass）と P1 2 件は反映されています。残りは実行可能性まわりの詰めです。

## P0

## P1
- `Phase 2 > 3` — 刺激の設計は正しくなったが、コマンドがそのままでは通らない。(1) attach 先の `verify` セッションは VERIFY.md「ホスト → 確認」の 1 行目が作って即 kill する使い捨てなので、この時点では存在しない。(2) `ssh -p 2222 localhost` は known_hosts が `[localhost]:2222` として別エントリになり、初回はホスト鍵の確認で止まる。(3) 背景実行で stdin を繋がないと端末から読もうとして SIGTTIN で止まり、「凍結していないのに応答が返らない」状態になって陰性対照（2 行の conf）まで曖昧になる / 45 秒待ちを 2 回やる検査で、毎回ここで手が止まるか、最悪クライアントが別要因で固まったまま「効いている」と誤読する / 手順を実行可能な形に落とす: 専用のセッション名で `tmux new-session -d -s clientalive -c /tmp` を先に作る（`verify` は使い捨てと衝突する）→ `( sleep 120 | TERM=xterm-256color script -q /dev/null ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes localhost -t 'tmux attach -t clientalive' ) &`（stdin と TERM は VERIFY.md 再接続・実機の `-D` 確認と同じ形）→ SIGUSR1。proxy の起動と停止、終わったあとの `tmux kill-session -t clientalive` も手順に含める。
- `Phase 2 > 4`, `動作確認` — このステップは `[AI🤖]` の Phase 2 に置かれているが、conf を 2 行に戻すのも 4 行に戻す `host-setup.sh` の実行も sudo が要るので AI では完結しない / 実行時に「ユーザーに 2 回頼む」ことが見えず、動作確認の節（人間タスクの一覧）にも載っていないので、人が席を外している間に止まる / ステップに `[人間👨‍💻]` を明示し、`動作確認` の箇条書きに「Phase 2 の陰性対照で conf を 2 行に戻す / スクリプトで 4 行に戻す（sudo 2 回）」を足す。
- `仕上げ` — コミットの手順が無い。今このワークツリーでは #8（画像添付）が `scripts/ssh-proxy.py` / `scripts/console-run.py` / `MobileIDE/Core/SSH/ImageUploader.swift` などを未コミットで触っている最中で、Phase 2 はその `ssh-proxy.py` を使う / `git add -A` 相当でまとめると別セッションの作業を巻き込んで push してしまう。逆に Phase 2 の途中で `ssh-proxy.py` の挙動（凍結の意味）が変わると検査結果が説明できなくなる / 仕上げに「`scripts/host-setup.sh` / `VERIFY.md` / `docs/tailscale.md` / この plan をパス指定でコミット」と書く。Phase 2 を回す前に `git status` で `ssh-proxy.py` に差分が出ていないか（出ていれば凍結の挙動が前提どおりか）を確認する 1 行も足す。

## P2
- `仕上げ` — `/retro` で残す対象が「sudo の分岐・brew bundle の罠」になっているが、今回いちばん高くついたのは keepalive の機序（送り手は sshd-session 自身なので `kill -STOP` では見えない・アプリのクライアントは `-D` で蹴られるので刺激に使えない）。CLAUDE.md の「ホスト側の癖」に 1 項目として残すと、次に同じ検査を書くときに再発しない。

## Q

````

**対応**: P0 なしで収束。P1 はすべて反映: Phase 2 > 3 を実行可能な形（専用セッション `clientalive`・`sleep 120 |` で stdin・`StrictHostKeyChecking=accept-new`・`BatchMode`・proxy と tmux の後片付け）に書き直し、陰性対照のステップに `[人間👨‍💻 sudo 2 回]` を明示して動作確認の節にも載せ、仕上げに「パス指定でコミット（`git add -A` は #8 を巻き込む）」と Phase 2 前の `ssh-proxy.py` の差分確認を足した（`git status` で #8 が `ssh-proxy.py` / `console-run.py` / `MobileIDE/**` を触っている最中なのを実測）/ P2: `/retro` の対象を keepalive の機序中心に書き換えた。
