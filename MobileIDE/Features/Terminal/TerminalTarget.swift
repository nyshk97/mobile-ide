import Foundation

/// 端末が入る tmux セッション。一覧（#5）の行から作る。接続先は `ConnectionSettings`。
struct TerminalTarget: Hashable {
    var sessionName: String
    var workingDirectory: String

    /// PTY のログインシェルに流し込むコマンド。detach でシェルも exit してチャネルが閉じる。
    /// `-A` は既存セッションがあれば attach、`-D` はそのとき他のクライアント（切れた前の自分など）を detach する
    var launchCommand: String {
        "tmux new-session -A -D -s \(sessionName) -c \(Self.shellEscape(workingDirectory)); exit"
    }

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
