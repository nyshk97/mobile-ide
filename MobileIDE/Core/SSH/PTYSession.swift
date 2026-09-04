import Citadel
import Crypto
import Foundation
import NIOCore
import NIOSSH
import Observation

/// SSH 接続 1 本と PTY チャネル 1 本の寿命を持つ。
///
/// Citadel の `withPTY` はクロージャを抜けるとチャネルが閉じるので、端末が開いている間は
/// クロージャ内で inbound を読み続ける Task を保持する。`close()` はその Task をキャンセルし接続を閉じる。
/// tmux セッション自体は Air 側で生き続ける（クライアントが切れるだけ）。
@Observable
@MainActor
final class PTYSession {
    enum State: Equatable {
        case idle
        case connecting
        case running
        case disconnected(String)
    }

    private(set) var state: State = .idle

    /// ホストからの出力。画面側が surface.feed に繋ぐ
    var onOutput: ((ArraySlice<UInt8>) -> Void)?

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var task: Task<Void, Never>?
    /// 直近に画面から通知されたサイズ。接続中に変わった分は接続完了時にまとめて送る
    private var latestSize: TerminalSize?
    /// write / changeSize の順序を守るための直列化（Task を素直に並べるとキー入力が前後しうる）
    private var pendingWrite: Task<Void, Never>?

    func start(target: TerminalTarget, size: TerminalSize, privateKey: Curve25519.Signing.PrivateKey) {
        switch state {
        case .connecting, .running: return
        case .idle, .disconnected: break
        }
        state = .connecting
        latestSize = size
        task = Task { [weak self] in
            do {
                let settings = SSHClientSettings(
                    host: target.host,
                    authenticationMethod: { .ed25519(username: target.user, privateKey: privateKey) },
                    hostKeyValidator: .acceptAnything()  // known_hosts 相当の固定は #4
                )
                let client = try await SSHClient.connect(to: settings)
                self?.client = client
                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: size.cols,
                    terminalRowHeight: size.rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([:])
                )
                try await client.withPTY(request) { inbound, outbound in
                    guard let self else { return }
                    self.writer = outbound
                    self.state = .running
                    print("TERMINAL connected \(target.user)@\(target.host) \(size.cols)x\(size.rows)")
                    fflush(stdout)
                    if let latest = self.latestSize, latest != size {
                        // 接続待ちの間にキーボード表示などでサイズが変わっていた
                        try await outbound.changeSize(cols: latest.cols, rows: latest.rows, pixelWidth: 0, pixelHeight: 0)
                        print("TERMINAL resized \(latest.cols)x\(latest.rows)")
                    }
                    try await outbound.write(ByteBuffer(string: target.launchCommand + "\n"))
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer), .stderr(let buffer):
                            self.onOutput?(ArraySlice(buffer.readableBytesView))
                        }
                    }
                }
                self?.finish("shell exited")
            } catch is CancellationError {
                self?.finish("closed")
            } catch let failure as SSHClient.CommandFailed {
                self?.finish("shell exited (code \(failure.exitCode))")
            } catch ChannelError.alreadyClosed {
                // シェルが exit してサーバー側からチャネルが閉じたあと、withPTY が close し直して出る。正常終了扱い
                self?.finish("shell exited")
            } catch {
                self?.finish("\(error)")
            }
        }
    }

    func send(_ data: Data) {
        guard let writer, state == .running else { return }
        enqueue { try await writer.write(ByteBuffer(bytes: data)) }
    }

    func resize(_ size: TerminalSize) {
        latestSize = size
        guard let writer, state == .running else { return }
        enqueue {
            try await writer.changeSize(cols: size.cols, rows: size.rows, pixelWidth: 0, pixelHeight: 0)
            print("TERMINAL resized \(size.cols)x\(size.rows)")
        }
    }

    func close() {
        task?.cancel()
        task = nil
        let client = self.client
        self.client = nil
        writer = nil
        Task { try? await client?.close() }
        if state != .idle { finish("closed") }
    }

    private func enqueue(_ operation: @escaping @Sendable () async throws -> Void) {
        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            do { try await operation() } catch { print("TERMINAL write failed \(error)") }
        }
    }

    private func finish(_ reason: String) {
        guard state != .disconnected(reason) else { return }
        writer = nil
        state = .disconnected(reason)
        print("TERMINAL disconnected \(reason)")
        fflush(stdout)
    }
}
