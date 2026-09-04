import SwiftUI

/// 端末画面。サーフェス 1 枚 + 接続中 / 切断のオーバーレイ + 再接続中のバナー。
struct TerminalScreen: View {
    let target: TerminalTarget

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts
    @Environment(\.scenePhase) private var scenePhase

    @State private var session = PTYSession()
    @State private var surface: any TerminalSurface = SwiftTermSurface()
    @State private var network = NetworkPathObserver()
    @State private var wired = false
    @State private var didAutomate = false
    @State private var isControlArmed = false
    @State private var isKeyboardVisible = false

    var body: some View {
        VStack(spacing: 0) {
            TerminalSurfaceView(surface: surface)
                .overlay { overlay }
                .overlay(alignment: .top) { reconnectBanner }
            KeyboardBar(isControlArmed: isControlArmed, isKeyboardVisible: isKeyboardVisible, perform: perform)
        }
        .navigationTitle(target.sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: wireUp)
        .onDisappear {
            network.stop()
            session.close()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: scenePhase) { _, phase in
            // 別アプリから戻った・ロック解除した。バックグラウンドでソケットが止められていたかもしれない
            if phase == .active { session.verifyAlive() }
        }
        .onChange(of: session.state) { _, newState in
            guard newState == .running, !didAutomate else { return }
            didAutomate = true
            Task { await runAutomation() }
        }
    }

    /// バーの操作。バーからの入力もエミュレータ経由（`surface.send`）で `onInput` に流れる
    private func perform(_ action: KeyboardBar.Action) {
        switch action {
        case .key(let key):
            surface.send(bytes: key.bytes(applicationCursor: surface.usesApplicationCursorKeys))
        case .toggleControl:
            surface.controlPending.toggle()
            isControlArmed = surface.controlPending
        case .toggleKeyboard:
            if isKeyboardVisible { surface.hideKeyboard() } else { surface.showKeyboard() }
        }
    }

    /// 自走検証: MOBILE_IDE_TERMINAL_TYPE の送信、MOBILE_IDE_PRESS_KEYS のバー操作の再現、MOBILE_IDE_PROBE_AFTER の生存判定。
    /// 最初に running になったときだけ走る（再接続のたびに文字列を送り直さない）
    private func runAutomation() async {
        if let text = LaunchOptions.terminalTextToType {
            try? await Task.sleep(for: .seconds(1))
            session.send(Data(text.utf8))
        }
        if let names = LaunchOptions.pressKeys {
            try? await Task.sleep(for: .seconds(1))
            for name in names {
                guard let action = KeyboardBar.Action(name: name) else {
                    print("KEYS unknown \(name)")
                    continue
                }
                perform(action)
                switch action {
                case .toggleControl: print("KEYS pressed ctrl armed=\(isControlArmed)")
                case .toggleKeyboard: print("KEYS pressed keyboard")
                case .key(let key): print("KEYS pressed \(key.rawValue) appCursor=\(surface.usesApplicationCursorKeys)")
                }
                fflush(stdout)
                try? await Task.sleep(for: .milliseconds(300))
            }
            print("KEYS done")
            fflush(stdout)
        }
        if let seconds = LaunchOptions.probeAfter {
            try? await Task.sleep(for: .seconds(seconds))
            print("TERMINAL probe start")
            fflush(stdout)
            session.verifyAlive()
        }
    }

    @ViewBuilder
    private var reconnectBanner: some View {
        if case .reconnecting(let attempt) = session.state {
            HStack(spacing: 10) {
                ProgressView()
                Text("再接続中… \(attempt) 回目")
                    .font(.footnote)
                Spacer()
                Button("今すぐ") { session.retryNow() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.state {
        case .idle, .connecting:
            ZStack {
                Color(.systemBackground).opacity(0.6)
                ProgressView("接続中…")
            }
        case .running, .reconnecting:
            EmptyView()
        case .disconnected(.shellExited(let reason)):
            stopped(title: "セッションを抜けました", detail: reason) {
                Button("再接続") { start() }
                    .buttonStyle(.borderedProminent)
            }
        case .disconnected(let reason):
            stopped(title: "切断されました", detail: reason.description) {
                Button("再接続") { start() }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(.hostKeyMismatch(let expected, let actual, let actualLine)):
            stopped(title: "ホスト鍵が変わりました", detail: "記録: \(expected)\n今回: \(actual)") {
                Button("新しい鍵を信用して再接続") {
                    knownHosts.set(actualLine, host: settings.host, port: settings.port)
                    start()
                }
                .buttonStyle(.borderedProminent)
                Text("Mac を入れ替えた・再インストールした覚えがなければ接続しないでください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .failed(let failure):
            stopped(title: "接続できませんでした", detail: failure.description) {
                Button("再試行") { start() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func stopped<Actions: View>(title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        ZStack {
            Color(.systemBackground).opacity(0.85)
            VStack(spacing: 12) {
                Image(systemName: "bolt.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions()
            }
            .padding()
        }
    }

    private func wireUp() {
        guard !wired else { return }
        wired = true
        surface.onInput = { data in session.send(data) }
        surface.onResize = { size in
            if session.state == .idle {
                start(size: size)
            } else {
                // connecting 中でも渡す。PTYSession が最新サイズを覚え、接続完了時に差分を送る
                session.resize(size)
            }
        }
        session.onOutput = { bytes in surface.feed(bytes) }
        surface.onControlReset = { isControlArmed = false }
        // Wi-Fi ↔ モバイル回線の切り替わりやオフラインからの復帰。無音で死んだ接続を探る契機
        network.onChange = { session.verifyAlive() }
        network.start()
        // sizeChanged が onAppear より先に来ていたらここで開く
        if let size = surface.currentSize, session.state == .idle {
            start(size: size)
        }
        DispatchQueue.main.async { surface.showKeyboard() }
    }

    private func start(size: TerminalSize? = nil) {
        guard let size = size ?? surface.currentSize else { return }
        let settings = settings, identity = identity, knownHosts = knownHosts
        session.start(target: target, size: size) {
            try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        }
    }
}
