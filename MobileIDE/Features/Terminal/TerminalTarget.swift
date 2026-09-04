import Foundation

/// 端末が入る tmux セッション。一覧（#5）の行から作る。接続先は `ConnectionSettings`。
struct TerminalTarget: Hashable {
    var sessionName: String
    var workingDirectory: String

    /// PTY のログインシェルに流し込むコマンド。detach でシェルも exit してチャネルが閉じる
    var launchCommand: String {
        "tmux new-session -A -s \(sessionName) -c \(workingDirectory); exit"
    }

    /// 自走検証（MOBILE_IDE_TERMINAL_AUTORUN=1）用。一覧を経由せずこのリポジトリのセッションを開く
    static let mobileIDE = TerminalTarget(sessionName: "mobile-ide", workingDirectory: "~/mobile-ide")
}
