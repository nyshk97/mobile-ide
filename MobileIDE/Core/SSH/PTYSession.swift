import Citadel
import Foundation
import NIOCore
import NIOSSH
import Observation

/// SSH 接続 1 本と PTY チャネル 1 本の寿命を持ち、回線断からの自動再接続を行う。
///
/// Citadel の `withPTY` はクロージャを抜けるとチャネルが閉じるので、端末が開いている間は
/// クロージャ内で inbound を読み続ける Task を保持する。`close()` はその Task をキャンセルし接続を閉じる。
/// tmux セッション自体はホスト側で生き続ける（クライアントが切れるだけ）。
///
/// 切れ方の分類: 回線が死んでも Citadel の inbound はエラーなしで普通に終わるので、
/// 終了時に `client.isConnected` と `onDisconnect` で「シェルが exit した」と「回線が切れた」を分ける。
/// 自動で張り直すのは回線断だけ。シェルの exit は画面の「再接続」ボタンに任せる。
@Observable
@MainActor
final class PTYSession {
    enum Disconnect: Equatable, CustomStringConvertible {
        /// tmux 内のシェルが exit / detach した（接続は生きていた）。自動では張り直さない
        case shellExited(String)
        /// 回線が切れた。自動再接続の対象
        case transport(String)
        /// アプリ側が閉じた
        case closed

        var description: String {
            switch self {
            case .shellExited(let reason): return reason
            case .transport(let reason): return reason
            case .closed: return "closed"
            }
        }
    }

    enum State: Equatable {
        case idle
        case connecting
        case running
        /// 回線断のあと張り直し中（attempt は 1 始まり）。端末の描画は残す
        case reconnecting(attempt: Int)
        case disconnected(Disconnect)
        /// 接続に失敗した（ホスト鍵不一致は画面で特別扱い）
        case failed(ConnectFailure)
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

    /// 再接続のために `start` の引数を持ち続ける
    private var target: TerminalTarget?
    private var connect: (@MainActor () async throws -> SSHClient)?
    /// 試行の世代。古い試行の Task が後から状態を触らないよう、状態を変える前に照合する
    private var generation = 0
    /// `reconnecting` の遅延待ち中か（`retryNow` はこのときだけ割り込む）
    private var sleeping = false
    /// 生存判定を 1 本に絞る
    private var probing = false
    /// バックグラウンドに入った時刻。復帰後の最初の `verifyAlive()` で読む
    private var backgroundedAt: ContinuousClock.Instant?
    /// バックグラウンド中か。この間は `verifyAlive()` を何もしない（経路変更で呼ばれても探らず、記録も消費しない）
    private var inBackground = false

    #if DEBUG
    deinit {
        print("TERMINAL session deinit \(LaunchOptions.objectID(self))")
        fflush(stdout)
    }
    #endif

    /// - Parameters:
    ///   - connect: `SSHConnection.connect` を包んだクロージャ。失敗は `ConnectFailure` で投げる
    func start(
        target: TerminalTarget,
        size: TerminalSize,
        connect: @escaping @MainActor () async throws -> SSHClient
    ) {
        switch state {
        case .connecting, .running, .reconnecting: return
        case .idle, .disconnected, .failed: break
        }
        self.target = target
        self.connect = connect
        latestSize = size
        state = .connecting
        launchAttempt(reconnectAttempt: nil, delayed: false)
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
        generation += 1
        task?.cancel()
        task = nil
        sleeping = false
        discardClient()
        if state != .idle { transition(.disconnected(.closed)) }
    }

    /// `reconnecting` の遅延待ちを飛ばして今すぐ試す（画面の「今すぐ」、経路の回復）
    func retryNow() {
        guard case .reconnecting(let attempt) = state, sleeping else { return }
        generation += 1
        task?.cancel()
        sleeping = false
        print("TERMINAL reconnecting attempt=\(attempt) delay=0 (retry now)")
        fflush(stdout)
        launchAttempt(reconnectAttempt: attempt, delayed: false)
    }

    /// 画面がバックグラウンドに入った（scenePhase）。`at` は検証用に過去の時刻を渡すため
    func enterBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundedAt = instant
        inBackground = true
    }

    /// フォアグラウンドに戻った（scenePhase）。記録を消費する `verifyAlive()` まで一続きで行う
    /// （分けると `inBackground == false` のまま記録が残り、後の経路変更が生きている接続を古い記録で切る）
    func enterForeground() {
        inBackground = false
        if let backgroundedAt {
            print("TERMINAL resume background=\(Int((ContinuousClock.now - backgroundedAt).components.seconds))s")
            fflush(stdout)
        }
        verifyAlive()
    }

    /// フォアグラウンド復帰・経路変更の契機で「まだ生きているか」を探る。
    /// `running` なら同じ接続で `true` を exec し、締め切りまでに返らなければ回線断として張り直す。
    /// ただしバックグラウンドに `ReconnectPolicy.staleAfterBackground` より長くいた直後なら、探らずに張り直す
    /// （サーバー側は ClientAlive で切っているはずで、RST が届かない Tailscale 経由では probe の 3 秒を丸ごと待つことになる）。
    /// `reconnecting` の遅延待ちなら即座に試す。それ以外は何もしない
    func verifyAlive() {
        // バックグラウンド中の経路変更で呼ばれても何もしない（探ると probing が立ったまま suspend し、記録も 0 秒として消える）
        guard !inBackground else { return }
        // 入口で読み捨てる。`.reconnecting` 経路に行ったときに残ると、後で生きている接続を古い記録で切ってしまう
        let sinceBackground = backgroundedAt.map { ContinuousClock.now - $0 }
        backgroundedAt = nil
        switch state {
        case .running: break
        case .reconnecting: retryNow(); return
        default: return
        }
        // probing の guard より先。経路変更（NWPathMonitor）と scenePhase のどちらが先に呼んでも効くように
        if let sinceBackground, sinceBackground > ReconnectPolicy.staleAfterBackground {
            lost("stale after background \(Int(sinceBackground.components.seconds))s", immediate: true)
            return
        }
        guard !probing, let client else { return }
        probing = true
        let gen = generation
        Task { [weak self] in
            let ok = await Self.probe(client)
            guard let self else { return }
            self.probing = false
            guard gen == self.generation, self.state == .running else { return }
            if ok {
                print("TERMINAL probe ok")
                fflush(stdout)
            } else {
                print("TERMINAL probe dead")
                fflush(stdout)
                self.lost("probe timed out", immediate: true)
            }
        }
    }

    // MARK: - 接続の試行

    /// 接続 → PTY → 起動コマンド → inbound を読み続ける。`reconnectAttempt` が nil なら初回接続。
    /// `delayed` なら試行番号に応じたバックオフを先に待つ
    private func launchAttempt(reconnectAttempt: Int?, delayed: Bool) {
        guard let target, let connect, let size = latestSize else { return }
        generation += 1
        let gen = generation
        task = Task { [weak self] in
            if let attempt = reconnectAttempt, delayed {
                let delay = ReconnectPolicy.delay(attempt: attempt)
                self?.sleeping = true
                try? await Task.sleep(for: delay)
                guard let self, gen == self.generation else { return }
                self.sleeping = false
                guard !Task.isCancelled else { return }
            }
            var client: SSHClient?
            do {
                let connected = try await connect()
                guard let self, gen == self.generation else {
                    try? await connected.close()
                    return
                }
                client = connected
                self.client = connected
                connected.onDisconnect { [weak self] in
                    Task { @MainActor in self?.connectionDidClose(connected, generation: gen) }
                }
                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: size.cols,
                    terminalRowHeight: size.rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([:])
                )
                try await connected.withPTY(request) { inbound, outbound in
                    guard gen == self.generation else { return }
                    self.writer = outbound
                    self.transition(.running)
                    print("TERMINAL connected \(target.sessionName) \(size.cols)x\(size.rows)")
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
                self.streamEnded(client: client, generation: gen, reason: "shell exited", reconnectAttempt: reconnectAttempt)
            } catch let failure as ConnectFailure {
                self?.connectFailed(failure, reconnectAttempt: reconnectAttempt, generation: gen)
            } catch is CancellationError {
                // close() / retryNow() が止めた。状態はそちらが変えている
            } catch let failure as SSHClient.CommandFailed {
                self?.streamEnded(client: client, generation: gen, reason: "shell exited (code \(failure.exitCode))", reconnectAttempt: reconnectAttempt)
            } catch ChannelError.alreadyClosed {
                // シェルが exit してサーバー側からチャネルが閉じたあと、withPTY が close し直して出る。正常終了扱い
                self?.streamEnded(client: client, generation: gen, reason: "shell exited", reconnectAttempt: reconnectAttempt)
            } catch {
                self?.streamEnded(client: client, generation: gen, reason: "\(error)", reconnectAttempt: reconnectAttempt, isError: true)
            }
        }
    }

    /// inbound が終わった。`running` なら、接続が生きていればシェルの exit、死んでいれば回線断。
    /// PTY を確立する前に終わったなら接続失敗と同じ扱い（初回は failed、再接続中は次の試行へ）
    private func streamEnded(client: SSHClient?, generation gen: Int, reason: String, reconnectAttempt: Int?, isError: Bool = false) {
        guard gen == generation else { return }
        switch state {
        case .running:
            let alive = client?.isConnected ?? false
            if alive, !isError {
                discardClient()
                transition(.disconnected(.shellExited(reason)))
            } else {
                lost(alive ? reason : "connection closed (\(reason))", immediate: false)
            }
        case .connecting, .reconnecting:
            connectFailed(.other("PTY を開けませんでした: \(reason)"), reconnectAttempt: reconnectAttempt, generation: gen)
        default:
            return
        }
    }

    private func connectFailed(_ failure: ConnectFailure, reconnectAttempt: Int?, generation gen: Int) {
        guard gen == generation else { return }
        discardClient()
        if case .hostKeyMismatch = failure {
            fail(failure)
            return
        }
        guard let attempt = reconnectAttempt else {
            fail(failure)
            return
        }
        print("TERMINAL reconnect failed attempt=\(attempt) \(failure)".replacingOccurrences(of: "\n", with: " "))
        fflush(stdout)
        scheduleReconnect(attempt: attempt + 1)
    }

    /// Citadel の closeFuture から。今の接続が閉じたなら回線断として扱う（inbound の終了より先に来ることがある）
    private func connectionDidClose(_ closed: SSHClient, generation gen: Int) {
        guard gen == generation, client === closed, state == .running else { return }
        lost("connection closed", immediate: false)
    }

    /// 回線断。古い接続を捨てて再接続に入る。`immediate` なら 1 回目の遅延を飛ばす（生存判定で死んでいた・書けなかった）
    private func lost(_ reason: String, immediate: Bool) {
        guard state == .running else { return }
        generation += 1
        task?.cancel()
        sleeping = false
        discardClient()
        print("TERMINAL lost \(reason)".replacingOccurrences(of: "\n", with: " "))
        fflush(stdout)
        scheduleReconnect(attempt: 1, delayed: !immediate)
    }

    private func scheduleReconnect(attempt: Int, delayed: Bool = true) {
        transition(.reconnecting(attempt: attempt))
        print("TERMINAL reconnecting attempt=\(attempt) delay=\(delayed ? ReconnectPolicy.delaySeconds(attempt: attempt) : 0)")
        fflush(stdout)
        launchAttempt(reconnectAttempt: attempt, delayed: delayed)
    }

    // MARK: - 補助

    private func enqueue(_ operation: @escaping @Sendable () async throws -> Void) {
        let previous = pendingWrite
        let gen = generation
        pendingWrite = Task { [weak self] in
            await previous?.value
            do {
                try await operation()
            } catch {
                print("TERMINAL write failed \(error)")
                // 書けない接続は死んでいる。inbound の終了を待たずに張り直す
                guard let self, gen == self.generation, self.state == .running else { return }
                self.lost("write failed: \(error)", immediate: true)
            }
        }
    }

    private func discardClient() {
        let client = self.client
        self.client = nil
        writer = nil
        if let client { Task { try? await client.close() } }
    }

    private func fail(_ failure: ConnectFailure) {
        transition(.failed(failure))
        print("TERMINAL failed \(failure)".replacingOccurrences(of: "\n", with: " "))
        fflush(stdout)
    }

    private func transition(_ new: State) {
        guard state != new else { return }
        state = new
        if case .disconnected(let reason) = new {
            print("TERMINAL disconnected \(reason)")
            fflush(stdout)
        }
    }

    /// 同じ接続で `true` を exec し、締め切り内に返れば生きている
    private static func probe(_ client: SSHClient) async -> Bool {
        do {
            let operations: [@Sendable () async throws -> Bool] = [
                { _ = try await client.executeCommand("true"); return true },
                {
                    try await Task.sleep(for: ReconnectPolicy.probeTimeout)
                    throw ProbeTimeout()
                },
            ]
            _ = try await SSHConnection.firstToFinish(operations)
            return true
        } catch {
            return false
        }
    }

    private struct ProbeTimeout: Error {}
}
