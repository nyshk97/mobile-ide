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

    /// バックグラウンドにこれより長くいた復帰は、探らずに張り直す。
    /// ホストの sshd は `scripts/host-setup.sh` が書く `ClientAliveInterval 15` / `ClientAliveCountMax 3` で、
    /// 無応答の接続を 15 × (3 + 1) = 60 秒超で切る（Air 実測 75 秒）。iPhone が suspend 中に切られると、サーバーの FIN/RST は
    /// Tailscale のトンネル停止中に落ちて端末側には届かず、probe の 3 秒を毎回払うことになる。
    /// 生きている接続を張り直しても `tmux new-session -A -D` で attach し直すだけ。**host-setup.sh の値を変えたらここも見直す**
    static let staleAfterBackground: Duration = .seconds(60)
}
