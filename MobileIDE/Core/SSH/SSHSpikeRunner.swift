import Citadel
import Crypto
import Foundation
import NIOCore
import NIOSSH

/// スパイクの 1 ステップの結果。
struct SpikeResult: Identifiable, Sendable {
    let id = UUID()
    let step: String
    let ok: Bool
    let detail: String
    let seconds: Double
}

/// #2 のスパイク本体。1 接続で exec → PTY → SFTP を順に試し、ステップごとの結果を返す。
///
/// 失敗したステップがあっても次へ進む（どのチャネルが駄目かを 1 回で把握するため）。
/// 結果は画面用のコールバックに加えて stdout にも `SPIKE <step> OK|NG <detail>` の形で出す
/// （`simctl launch --console` / `devicectl ... --console` で Mac 側から読むため）。
enum SSHSpikeRunner {
    static let stepTimeout: Duration = .seconds(20)

    static func run(
        host: String,
        port: Int = 22,
        user: String,
        privateKey: Curve25519.Signing.PrivateKey,
        onResult: @escaping @Sendable (SpikeResult) async -> Void
    ) async {
        func report(_ step: String, _ ok: Bool, _ detail: String, since start: ContinuousClock.Instant) async {
            let seconds = Double((ContinuousClock.now - start).components.attoseconds) / 1e18
                + Double((ContinuousClock.now - start).components.seconds)
            let result = SpikeResult(step: step, ok: ok, detail: detail, seconds: seconds)
            print("SPIKE \(step) \(ok ? "OK" : "NG") \(detail.replacingOccurrences(of: "\n", with: "\\n"))")
            fflush(stdout)
            await onResult(result)
        }

        // 1. connect + 認証
        var start = ContinuousClock.now
        let client: SSHClient
        do {
            let settings = SSHClientSettings(
                host: host,
                port: port,
                authenticationMethod: { .ed25519(username: user, privateKey: privateKey) },
                hostKeyValidator: .acceptAnything()  // スパイク限定。known_hosts 相当の固定は #4 で決める
            )
            client = try await withTimeout(stepTimeout) { try await SSHClient.connect(to: settings) }
            await report("connect", true, "\(user)@\(host):\(port) publickey", since: start)
        } catch {
            await report("connect", false, "\(error)", since: start)
            return
        }

        // 2. exec
        start = .now
        do {
            let buffer = try await withTimeout(stepTimeout) { try await client.executeCommand("echo hello") }
            let text = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            await report("exec", text == "hello", text, since: start)
        } catch {
            await report("exec", false, "\(error)", since: start)
        }

        // 3. PTY（対話シェル。.zshrc を読むので PATH 前置き無しで tmux が見えるはず）
        start = .now
        do {
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: 80,
                terminalRowHeight: 24,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: .init([.ECHO: 1])
            )
            let collected = try await withTimeout(stepTimeout) {
                var collected = ""
                try await client.withPTY(request) { inbound, outbound in
                    try await outbound.write(ByteBuffer(string: "tmux -V; exit\n"))
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer), .stderr(let buffer):
                            collected += String(buffer: buffer)
                        }
                        // シェルが exit するとストリームが終わる想定。念のため目印が出たら抜ける
                        if collected.contains("tmux 3.") && collected.contains("exit") { break }
                    }
                }
                return collected
            }
            // 出力はプロンプトの装飾（ANSI エスケープ）が大半なので、tmux の版数行だけを抜き出す
            let plain = stripANSI(collected)
            let versionLine = plain.split(whereSeparator: \.isNewline).first { $0.contains("tmux 3.") }
            let ok = versionLine != nil
            await report("pty", ok, versionLine.map(String.init) ?? String(plain.suffix(200)), since: start)
        } catch {
            await report("pty", false, "\(error)", since: start)
        }

        // 4. SFTP
        start = .now
        do {
            let path = try await withTimeout(stepTimeout) {
                let sftp = try await client.openSFTP()
                let path = try await sftp.getRealPath(atPath: ".")
                try await sftp.close()
                return path
            }
            await report("sftp", path.hasPrefix("/"), path, since: start)
        } catch {
            await report("sftp", false, "\(error)", since: start)
        }

        // 5. close
        start = .now
        do {
            try await client.close()
            await report("close", true, "", since: start)
        } catch {
            await report("close", false, "\(error)", since: start)
        }
    }

    /// CSI / OSC などの ANSI エスケープシーケンスと CR を落とす（表示用）。
    private static func stripANSI(_ text: String) -> String {
        let pattern = "\u{1B}\\[[0-?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*(\u{07}|\u{1B}\\\\)|\u{1B}[@-Z\\\\-_]|\r"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    struct TimeoutError: Error, CustomStringConvertible {
        let description = "timed out"
    }

    /// `operation` が `duration` 以内に終わらなければ TimeoutError。
    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
