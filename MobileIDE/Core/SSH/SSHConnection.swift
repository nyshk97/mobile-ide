import Citadel
import Foundation
import NIOCore
import NIOSSH

/// 接続失敗の分類。ホスト鍵の不一致だけは画面で特別扱い（新旧指紋と「新しい鍵を信用」）する
enum ConnectFailure: Error, Equatable, CustomStringConvertible {
    case hostKeyMismatch(expected: String, actual: String, actualLine: String)
    case other(String)

    var description: String {
        switch self {
        case .hostKeyMismatch(let expected, let actual, _):
            return "ホスト鍵が変わりました\n記録: \(expected)\n今回: \(actual)"
        case .other(let message):
            return message
        }
    }
}

/// SSH 接続を作る唯一の入口。設定・この端末の鍵・ホスト鍵の記録をまとめて `SSHClient` にする。
enum SSHConnection {
    @MainActor
    static func connect(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async throws -> SSHClient {
        let host = settings.host, port = settings.port, user = settings.user
        let privateKey = identity.privateKey
        let expected = knownHosts.line(host: host, port: port).flatMap { try? NIOSSHPublicKey(openSSHPublicKey: $0) }
        let validator = TOFUHostKeyValidator(expected: expected)
        let clientSettings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .ed25519(username: user, privateKey: privateKey) },
            hostKeyValidator: .custom(validator)
        )

        func recordOutcome() {
            switch validator.outcome {
            case .trusted(let key):
                knownHosts.set(key.openSSHLine, host: host, port: port)
                print("SSH hostkey trusted \(key.sha256Fingerprint)")
            case .ok(let key):
                print("SSH hostkey ok \(key.sha256Fingerprint)")
            case .mismatch(let expected, let actual):
                print("SSH hostkey mismatch expected=\(expected.sha256Fingerprint) actual=\(actual.sha256Fingerprint)")
            case nil:
                break
            }
        }

        // ホスト鍵の検証に失敗しても Citadel の connect はすぐ返らない（ハンドシェイク失敗で待ち続ける）ので、
        // validator の結果を監視して不一致なら即座に失敗させる。全体にもタイムアウトを付ける。
        // connect はキャンセルできないので TaskGroup（全子タスクの完了を待つ）ではなく「最初に終わった側を採る」形にし、
        // 負けた connect が後から成功したら閉じる
        let connectTask = Task { try await SSHClient.connect(to: clientSettings) }
        do {
            let client = try await firstToFinish([
                { try await connectTask.value },
                {
                    while true {
                        try await Task.sleep(for: .milliseconds(100))
                        if case .mismatch = validator.outcome { throw TOFUHostKeyValidator.HostKeyMismatch() }
                    }
                },
                {
                    try await Task.sleep(for: connectTimeout)
                    throw ConnectTimeout()
                },
            ])
            recordOutcome()
            return client
        } catch {
            Task { if let late = try? await connectTask.value { try? await late.close() } }
            recordOutcome()
            if case .mismatch(let expected, let actual) = validator.outcome {
                throw ConnectFailure.hostKeyMismatch(
                    expected: expected.sha256Fingerprint,
                    actual: actual.sha256Fingerprint,
                    actualLine: actual.openSSHLine
                )
            }
            if error is ConnectTimeout {
                throw ConnectFailure.other("接続がタイムアウトしました（\(host):\(port)）")
            }
            throw ConnectFailure.other("\(error)")
        }
    }

    static let connectTimeout: Duration = .seconds(20)

    struct ConnectTimeout: Error {}

    /// 最初に終わった操作の結果を返し、残りはキャンセルする（sleep 系はキャンセルで止まる。connect や exec は止まらないが放置してよい）。
    /// `PTYSession` の生存判定（exec と締め切りの競走）でも使う
    static func firstToFinish<T: Sendable>(_ operations: [@Sendable () async throws -> T]) async throws -> T {
        let once = FirstToFinishState()
        return try await withCheckedThrowingContinuation { continuation in
            once.tasks = operations.map { operation in
                Task {
                    let result: Result<T, Error>
                    do { result = .success(try await operation()) } catch { result = .failure(error) }
                    guard once.claim() else { return }
                    once.tasks.forEach { $0.cancel() }
                    continuation.resume(with: result)
                }
            }
        }
    }

    struct TestResult: Equatable {
        var ok: Bool
        var detail: String
        var seconds: Double
        /// 失敗がホスト鍵不一致だったときの内訳
        var mismatch: ConnectFailure?
    }

    static func lastMismatch(in result: TestResult) -> (expected: String, actual: String, actualLine: String)? {
        if case .hostKeyMismatch(let expected, let actual, let actualLine)? = result.mismatch {
            return (expected, actual, actualLine)
        }
        return nil
    }

    /// 接続 → `echo ok` → 切断。設定画面の接続テスト
    @MainActor
    static func test(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async -> TestResult {
        let start = ContinuousClock.now
        func elapsed() -> Double {
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        do {
            let client = try await connect(settings: settings, identity: identity, knownHosts: knownHosts)
            let output = try await client.executeCommand("echo ok")
            try? await client.close()
            let text = String(buffer: output).trimmingCharacters(in: .whitespacesAndNewlines)
            let result = TestResult(ok: text == "ok", detail: text, seconds: elapsed())
            print("SSH test \(result.ok ? "OK" : "NG") \(result.detail)")
            return result
        } catch let failure as ConnectFailure {
            if case .hostKeyMismatch = failure {
                print("SSH test NG hostKeyMismatch")
                return TestResult(ok: false, detail: failure.description, seconds: elapsed(), mismatch: failure)
            }
            print("SSH test NG \(failure.description)")
            return TestResult(ok: false, detail: failure.description, seconds: elapsed())
        } catch {
            print("SSH test NG \(error)")
            return TestResult(ok: false, detail: "\(error)", seconds: elapsed())
        }
    }
}

/// `firstToFinish` の「最初の 1 回だけ resume する」状態。ジェネリック関数の中に型は置けないのでファイルスコープ
private final class FirstToFinishState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    var tasks: [Task<Void, Never>] = []

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
