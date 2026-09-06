import Foundation

/// 端末が入る tmux セッション。一覧（#5）の行から作る。接続先は `ConnectionSettings`。
struct TerminalTarget: Hashable {
    var sessionName: String
    var workingDirectory: String

    /// PTY のログインシェルに流し込むコマンド。detach でシェルも exit してチャネルが閉じる。
    /// `-A` は既存セッションがあれば attach、`-D` はそのとき他のクライアント（切れた前の自分など）を detach する。
    /// attach に続けて `mouseSetup` を同じ tmux コマンド列で流す（`\;` はシェルを通ると `;` になり tmux のコマンド区切り）
    var launchCommand: String {
        let attach = "tmux new-session -A -D -s \(sessionName) -c \(Self.shellEscape(workingDirectory))"
        return ([attach] + Self.mouseSetup).joined(separator: " \\; ") + "; exit"
    }

    /// アプリが開くセッションだけ tmux のマウスを有効にする。tmux のクライアントは代替画面で描くので外側の端末に
    /// スクロールバックが無く、素のシェルの一本指スクロールは tmux が copy-mode で処理するしかない（端末側は
    /// `WheelScrollingTerminalView` が一本指ドラッグをホイールにする）。Claude Code のようにマウスを使うアプリには
    /// tmux がそのまま転送する。copy-mode のホイールは既定の 5 行を 1 行にして指 1 行 = 1 行にする。`mode-keys` が vi の
    /// 環境（`EDITOR` に vi が含まれると自動でそうなる）では copy-mode-vi テーブルが使われるので両方に流す。
    /// 注意: `mouse` はセッションオプションなのでアプリが detach した後も残り、同じセッションに Mac から attach しても
    /// mouse on のまま。`bind-key` はサーバー全体・サーバーが生きている限り恒久で、接続のたびに上書きする。
    /// `'\;'` は `\;` のまま tmux に届き bind の中の区切りになる
    static let mouseSetup = [
        "set-option mouse on",
        "bind-key -T copy-mode WheelUpPane select-pane '\\;' send-keys -X -N 1 scroll-up",
        "bind-key -T copy-mode WheelDownPane select-pane '\\;' send-keys -X -N 1 scroll-down",
        "bind-key -T copy-mode-vi WheelUpPane select-pane '\\;' send-keys -X -N 1 scroll-up",
        "bind-key -T copy-mode-vi WheelDownPane select-pane '\\;' send-keys -X -N 1 scroll-down",
    ]

    /// シェルの単語として安全にする。`[A-Za-z0-9_/.-]` 以外はバックスラッシュでエスケープする。
    /// 先頭の `~` だけは素通しにしてチルダ展開を残す（自走用の `~/mobile-ide`）
    static func shellEscape(_ raw: String) -> String {
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/.-")
        var out = ""
        for (index, ch) in raw.enumerated() {
            if safe.contains(ch) || (index == 0 && ch == "~") {
                out.append(ch)
            } else {
                out.append("\\")
                out.append(ch)
            }
        }
        return out.isEmpty ? "''" : out
    }

    /// 自走検証（MOBILE_IDE_TERMINAL_AUTORUN=1）用。一覧を経由せずこのリポジトリのセッションを開く
    static let mobileIDE = TerminalTarget(sessionName: "mobile-ide", workingDirectory: "~/mobile-ide")
}
