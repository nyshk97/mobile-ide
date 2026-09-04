import Foundation
import NIOCore
import NIOSSH

/// TOFU（初回信用・以降照合）のホスト鍵検証。
///
/// NIO のイベントループから呼ばれるので、記録先（KnownHostStore）には触らず結果だけ持ち帰る。
/// 呼び出し側（SSHConnection）が接続の成否に関わらず `outcome` を読んで記録・エラー変換する。
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    enum Outcome: Equatable {
        /// 未登録だったので今回の鍵を信用した
        case trusted(NIOSSHPublicKey)
        /// 登録済みの鍵と一致
        case ok(NIOSSHPublicKey)
        /// 登録済みの鍵と違う（接続は失敗させる）
        case mismatch(expected: NIOSSHPublicKey, actual: NIOSSHPublicKey)
    }

    struct HostKeyMismatch: Error {}

    private let expected: NIOSSHPublicKey?
    private let lock = NSLock()
    private var _outcome: Outcome?

    init(expected: NIOSSHPublicKey?) {
        self.expected = expected
    }

    var outcome: Outcome? {
        lock.lock(); defer { lock.unlock() }
        return _outcome
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let outcome: Outcome
        if let expected {
            outcome = expected == hostKey ? .ok(hostKey) : .mismatch(expected: expected, actual: hostKey)
        } else {
            outcome = .trusted(hostKey)
        }
        lock.lock(); _outcome = outcome; lock.unlock()
        if case .mismatch = outcome {
            validationCompletePromise.fail(HostKeyMismatch())
        } else {
            validationCompletePromise.succeed(())
        }
    }
}
