import SwiftUI

/// 端末画面。サーフェス 1 枚 + 接続中 / 切断のオーバーレイ。
struct TerminalScreen: View {
    let target: TerminalTarget

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts

    @State private var session = PTYSession()
    @State private var surface: any TerminalSurface = SwiftTermSurface()
    @State private var wired = false

    var body: some View {
        TerminalSurfaceView(surface: surface)
            .overlay { overlay }
            .navigationTitle(target.sessionName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: wireUp)
            .onDisappear { session.close() }
            .onChange(of: session.state) { _, newState in
                guard newState == .running, let text = LaunchOptions.terminalTextToType else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    session.send(Data(text.utf8))
                }
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
        case .disconnected(let reason):
            stopped(title: "切断されました", detail: reason) {
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
        case .running:
            EmptyView()
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
        // sizeChanged が onAppear より先に来ていたらここで開く
        if let size = surface.currentSize, session.state == .idle {
            start(size: size)
        }
        DispatchQueue.main.async { surface.focus() }
    }

    private func start(size: TerminalSize? = nil) {
        guard let size = size ?? surface.currentSize else { return }
        let settings = settings, identity = identity, knownHosts = knownHosts
        session.start(target: target, size: size) {
            try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        }
    }
}
