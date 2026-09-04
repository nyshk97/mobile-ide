import Foundation

/// 自走検証用の環境変数。シミュレータは `SIMCTL_CHILD_`、実機は `DEVICECTL_CHILD_` のプレフィックスで渡す
/// （`scripts/console-run.py --env KEY=VALUE` が付ける）。
///
/// - `MOBILE_IDE_TERMINAL_AUTORUN=1`: 起動直後に `mobile-ide` の端末画面を開く（一覧を経由しない）
/// - `MOBILE_IDE_OPEN_PROJECT=<sessionName>`: 一覧を読み終えたら該当行の端末を開く
/// - `MOBILE_IDE_TERMINAL_TYPE=<text>`: 端末接続後 1 秒待ってその文字列を送る（`\n` は改行に展開）
/// - `MOBILE_IDE_CONNECTION_TEST=1`: 起動直後に設定画面を開いて接続テストを実行する
/// - `MOBILE_IDE_HOST` / `MOBILE_IDE_PORT` / `MOBILE_IDE_USER`: 接続設定を上書き（保存はしない）
/// - `MOBILE_IDE_KNOWNHOST=forget` / `=<OpenSSH 公開鍵行>`（DEBUG のみ）: 起動時に接続先のホスト鍵の記録を消す / 差し替える。
///   TOFU の不一致経路を外から起こすため（シミュレータの UserDefaults は外から安全に書き換えられない）
enum LaunchOptions {
    private static let env = ProcessInfo.processInfo.environment

    static var terminalAutorun: Bool { env["MOBILE_IDE_TERMINAL_AUTORUN"] == "1" }
    static var terminalTextToType: String? {
        env["MOBILE_IDE_TERMINAL_TYPE"]?.replacingOccurrences(of: "\\n", with: "\n")
    }
    static var openProject: String? { env["MOBILE_IDE_OPEN_PROJECT"].flatMap { $0.isEmpty ? nil : $0 } }
    static var connectionTest: Bool { env["MOBILE_IDE_CONNECTION_TEST"] == "1" }
    static var hostOverride: String? { env["MOBILE_IDE_HOST"] }
    static var portOverride: Int? { env["MOBILE_IDE_PORT"].flatMap(Int.init) }
    static var userOverride: String? { env["MOBILE_IDE_USER"] }

    enum KnownHostOverride {
        case forget
        case replace(String)
    }

    static var knownHostOverride: KnownHostOverride? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_KNOWNHOST"], !value.isEmpty else { return nil }
        return value == "forget" ? .forget : .replace(value)
        #else
        return nil
        #endif
    }
}
