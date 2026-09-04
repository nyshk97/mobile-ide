import Foundation

/// 端末が入る tmux セッション。#3 では 1 つ固定（プロジェクト一覧化は #5）。接続先は `ConnectionSettings`。
struct TerminalTarget: Equatable {
    var sessionName: String
    var workingDirectory: String

    /// PTY のログインシェルに流し込むコマンド。detach でシェルも exit してチャネルが閉じる
    var launchCommand: String {
        "tmux new-session -A -s \(sessionName) -c \(workingDirectory); exit"
    }

    static let mobileIDE = TerminalTarget(sessionName: "mobile-ide", workingDirectory: "~/mobile-ide")
}
