import Foundation
import Observation

/// ホスト鍵の記録（known_hosts 相当）。キーは `host:port`、値は OpenSSH の公開鍵行。
@Observable
@MainActor
final class KnownHostStore {
    private let defaults: UserDefaults
    private static let prefix = "knownhosts."
    /// 表示用のミラー。@Observable が追跡できるよう stored property に持つ
    private(set) var entries: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.prefix) {
            if let line = value as? String { entries[String(key.dropFirst(Self.prefix.count))] = line }
        }
    }

    static func id(host: String, port: Int) -> String { "\(host):\(port)" }

    func line(host: String, port: Int) -> String? {
        entries[Self.id(host: host, port: port)]
    }

    func set(_ line: String, host: String, port: Int) {
        let id = Self.id(host: host, port: port)
        entries[id] = line
        defaults.set(line, forKey: Self.prefix + id)
    }

    func remove(host: String, port: Int) {
        let id = Self.id(host: host, port: port)
        entries.removeValue(forKey: id)
        defaults.removeObject(forKey: Self.prefix + id)
    }
}
