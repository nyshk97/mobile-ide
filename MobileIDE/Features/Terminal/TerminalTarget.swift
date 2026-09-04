import Foundation

/// 端末が繋ぐ先。#3 ではセッション名と作業ディレクトリを固定（プロジェクト一覧化は #5）。
/// ホスト・ユーザーはスパイク画面の保存値を流用する（正式な接続設定は #4）。
struct TerminalTarget: Equatable {
    var host: String
    var user: String
    var sessionName: String
    var workingDirectory: String

    /// PTY のログインシェルに流し込むコマンド。detach でシェルも exit してチャネルが閉じる
    var launchCommand: String {
        "tmux new-session -A -s \(sessionName) -c \(workingDirectory); exit"
    }

    static func current() -> TerminalTarget {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        return TerminalTarget(
            host: env["MOBILE_IDE_SPIKE_HOST"] ?? defaults.string(forKey: "spike.host") ?? "127.0.0.1",
            user: env["MOBILE_IDE_SPIKE_USER"] ?? defaults.string(forKey: "spike.user") ?? "",
            sessionName: "mobile-ide",
            workingDirectory: "~/mobile-ide"
        )
    }
}

/// 自走検証用の環境変数。
/// - `MOBILE_IDE_TERMINAL_AUTORUN=1`: 起動直後に端末画面を開く
/// - `MOBILE_IDE_TERMINAL_TYPE=<text>`: 接続後 1 秒待ってその文字列を送る（`\n` は改行に展開）
enum TerminalAutorun {
    private static let env = ProcessInfo.processInfo.environment
    static var isRequested: Bool { env["MOBILE_IDE_TERMINAL_AUTORUN"] == "1" }
    static var textToType: String? {
        env["MOBILE_IDE_TERMINAL_TYPE"]?.replacingOccurrences(of: "\\n", with: "\n")
    }
}
