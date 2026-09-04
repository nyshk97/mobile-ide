import Foundation
import Observation

/// 接続先（1 台固定）。UserDefaults の `connection.*` に持つ。
@Observable
@MainActor
final class ConnectionSettings {
    var host: String { didSet { defaults.set(host, forKey: "connection.host") } }
    var port: Int { didSet { defaults.set(port, forKey: "connection.port") } }
    var user: String { didSet { defaults.set(user, forKey: "connection.user") } }

    private let defaults: UserDefaults

    var isConfigured: Bool { !host.isEmpty && !user.isEmpty && (1...65535).contains(port) }

    /// DEBUG 用: 上書き値を setter 経由で保存する（手入力と同じ didSet を通す）。init 内では didSet が走らないので分ける
    func saveLaunchOverridesIfRequested() {
        guard LaunchOptions.saveSettings else { return }
        if let h = LaunchOptions.hostOverride { host = h }
        if let p = LaunchOptions.portOverride { port = p }
        if let u = LaunchOptions.userOverride { user = u }
        print("HOME settings saved host=\(host) port=\(port) user=\(user)")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 環境変数の上書きは自走検証用。メモリ上だけに適用し、保存は didSet が走る編集時に任せる
        host = LaunchOptions.hostOverride ?? defaults.string(forKey: "connection.host") ?? ""
        let storedPort = defaults.integer(forKey: "connection.port")
        port = LaunchOptions.portOverride ?? (storedPort == 0 ? 22 : storedPort)
        user = LaunchOptions.userOverride ?? defaults.string(forKey: "connection.user") ?? ""
    }
}
