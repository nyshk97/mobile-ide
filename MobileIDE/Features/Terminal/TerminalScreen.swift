import SwiftUI

/// 端末画面。サーフェス 1 枚 + 接続中 / 切断のオーバーレイ。
struct TerminalScreen: View {
    let target: TerminalTarget

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
                guard newState == .running, let text = TerminalAutorun.textToType else { return }
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
            ZStack {
                Color(.systemBackground).opacity(0.85)
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("切断されました")
                        .font(.headline)
                    Text(reason)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("再接続") { start() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        case .running:
            EmptyView()
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
        session.start(target: target, size: size, privateKey: DevKeyStore.loadOrCreate())
    }
}
