import Foundation
import Network
import Observation

/// ネットワーク経路の変化（Wi-Fi ↔ モバイル回線、オフライン → 復帰）を知らせる `NWPathMonitor` の薄いラッパ。
///
/// 無音で死んだ SSH 接続は経路が変わっても何も起きないので、経路が使える状態に変わった契機で生存判定を促す。
@Observable
@MainActor
final class NetworkPathObserver {
    /// 経路が使える状態に「変わった」とき（初回の通知は除く）
    var onChange: (() -> Void)?

    private var monitor: NWPathMonitor?
    private var lastKey: String?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPath は Sendable でないので、必要な値だけ取り出してから main に戻す
            let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let satisfied = path.status == .satisfied
            let key = "\(satisfied ? "up" : "down") \(interfaces)"
            Task { @MainActor in self?.handle(key: key, satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastKey = nil
    }

    private func handle(key: String, satisfied: Bool) {
        defer { lastKey = key }
        guard let previous = lastKey, previous != key else { return }
        print("NETWORK path \(key)")
        fflush(stdout)
        if satisfied { onChange?() }
    }
}
