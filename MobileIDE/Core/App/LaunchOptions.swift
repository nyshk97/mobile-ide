import Foundation

/// 自走検証用の環境変数。シミュレータは `SIMCTL_CHILD_`、実機は `DEVICECTL_CHILD_` のプレフィックスで渡す
/// （`scripts/console-run.py --env KEY=VALUE` が付ける）。
///
/// - `MOBILE_IDE_TERMINAL_AUTORUN=1`: 起動直後に `mobile-ide` の端末画面を開く（一覧を経由しない）
/// - `MOBILE_IDE_OPEN_PROJECT=<sessionName>`: 一覧を読み終えたら該当行の端末を開く
/// - `MOBILE_IDE_TERMINAL_TYPE=<text>`: 端末接続後 1 秒待ってその文字列を送る（`\n` は改行に展開）
/// - `MOBILE_IDE_PRESS_KEYS=tab,enter,claude,gpull,/dig,keyboard`（DEBUG のみ）: 端末接続後、キーボードバーの操作を順に再現する。
///   `TerminalKey` の名前（バーに無い esc 等も可）、ショートカット（`claude` / `codex` / `gpull` / `gpush` / `/` 始まり）、`keyboard`
/// - `MOBILE_IDE_PROBE_AFTER=<秒>`（DEBUG のみ）: 端末接続の N 秒後に生存判定（フォアグラウンド復帰と同じ経路）を呼ぶ。
///   シミュレータでは scenePhase を外から起こせないため
/// - `MOBILE_IDE_UPLOAD_FILE=<path>[,<path>…]`（DEBUG のみ）: 端末接続後、ホスト側のそのファイルを画像添付と同じ経路
///   （変換 → SFTP → `@path ` の流し込み）で送る。`MOBILE_IDE_UPLOAD_AFTER=<秒>`（既定 0）で発火を遅らせる
/// - `MOBILE_IDE_CONNECTION_TEST=1`: 起動直後に設定画面を開いて接続テストを実行する
/// - `MOBILE_IDE_HOST` / `MOBILE_IDE_PORT` / `MOBILE_IDE_USER`: 接続設定を上書き（保存はしない）
/// - `MOBILE_IDE_SAVE_SETTINGS=1`（DEBUG のみ）: 上書き値を UserDefaults にも保存する。手入力と同じ保存経路（setter → didSet）を自走検証・焼き込みに使う
/// - `MOBILE_IDE_KNOWNHOST=forget` / `=<OpenSSH 公開鍵行>`（DEBUG のみ）: 起動時に接続先のホスト鍵の記録を消す / 差し替える。
///   TOFU の不一致経路を外から起こすため（シミュレータの UserDefaults は外から安全に書き換えられない）
enum LaunchOptions {
    private static let env = ProcessInfo.processInfo.environment

    static var terminalAutorun: Bool { env["MOBILE_IDE_TERMINAL_AUTORUN"] == "1" }
    static var terminalTextToType: String? {
        env["MOBILE_IDE_TERMINAL_TYPE"]?.replacingOccurrences(of: "\\n", with: "\n")
    }
    static var pressKeys: [String]? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_PRESS_KEYS"], !value.isEmpty else { return nil }
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #else
        return nil
        #endif
    }
    static var probeAfter: Double? {
        #if DEBUG
        return env["MOBILE_IDE_PROBE_AFTER"].flatMap(Double.init)
        #else
        return nil
        #endif
    }
    static var uploadFiles: [String]? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_UPLOAD_FILE"], !value.isEmpty else { return nil }
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #else
        return nil
        #endif
    }
    static var uploadAfter: Double {
        #if DEBUG
        return env["MOBILE_IDE_UPLOAD_AFTER"].flatMap(Double.init) ?? 0
        #else
        return 0
        #endif
    }
    static var openProject: String? { env["MOBILE_IDE_OPEN_PROJECT"].flatMap { $0.isEmpty ? nil : $0 } }
    static var connectionTest: Bool { env["MOBILE_IDE_CONNECTION_TEST"] == "1" }
    static var hostOverride: String? { env["MOBILE_IDE_HOST"] }
    static var portOverride: Int? { env["MOBILE_IDE_PORT"].flatMap(Int.init) }
    static var userOverride: String? { env["MOBILE_IDE_USER"] }
    static var saveSettings: Bool {
        #if DEBUG
        return env["MOBILE_IDE_SAVE_SETTINGS"] == "1"
        #else
        return false
        #endif
    }

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
