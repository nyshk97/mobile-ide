import Foundation

/// 再接続の間隔と生存判定の締め切り。値はここだけで持つ。
enum ReconnectPolicy {
    /// n 回目（1 始まり）の試行までに待つ秒数。1, 2, 4, 8 と倍々にして 15 秒で頭打ち
    static func delaySeconds(attempt: Int) -> Int {
        guard attempt >= 1 else { return 0 }
        let doubled = 1 << min(attempt - 1, 4)  // 1, 2, 4, 8, 16
        return min(doubled, maxDelaySeconds)
    }

    static func delay(attempt: Int) -> Duration {
        .seconds(delaySeconds(attempt: attempt))
    }

    static let maxDelaySeconds = 15

    /// フォアグラウンド復帰時などの生存判定（`true` の exec）に待つ上限
    static let probeTimeout: Duration = .seconds(3)
}
