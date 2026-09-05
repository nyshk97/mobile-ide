import SwiftUI

/// 端末画面。サーフェス 1 枚 + 接続中 / 切断のオーバーレイ + 再接続中のバナー。
struct TerminalScreen: View {
    let target: TerminalTarget

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var session = PTYSession()
    @State private var surface: any TerminalSurface = SwiftTermSurface()
    @State private var network = NetworkPathObserver()
    @State private var attachments = AttachmentFlow()
    @State private var wired = false
    @State private var didAutomate = false
    @State private var isKeyboardVisible = false
    #if DEBUG
    /// 直前に閉じた画面の端末 view。UIKit のキーボードは最後の first responder を 1 個だけ握り続けるので、
    /// 「1 つ前の view が解放されたか」で有界であることを見る（`MOBILE_IDE_OPEN_TIMES=2`）
    private static weak var lastClosedView: UIView?
    private static var closeCount = 0
    #endif

    var body: some View {
        VStack(spacing: 0) {
            TerminalSurfaceView(surface: surface)
                .overlay { overlay }
                .overlay(alignment: .top) { topBanner }
            KeyboardBar(isKeyboardVisible: isKeyboardVisible, perform: perform)
        }
        .navigationTitle(target.sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AttachmentButton(isBusy: attachments.isBusy) { datas in await attach(datas) }
            }
        }
        .alert(item: $attachments.alert) { alert in
            SwiftUI.Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onAppear(perform: wireUp)
        .onDisappear {
            // wireUp のクロージャは View 構造体（= @State の箱）を捕まえるので、外さないと session ⇄ surface の循環で両方が残る
            network.onChange = nil
            network.stop()
            session.onOutput = nil
            session.close()
            surface.tearDown()
            #if DEBUG
            // 端末 view が解放されたか。current はキーボードを出した後だと UIKit が最後の first responder として握るので false になる。
            // previous（1 つ前に閉じた画面の view）が true なら、握られるのは 1 個だけで積み上がらない。解放は遅れることがあるので最大 5 秒待つ
            weak var view: UIView? = surface.view
            weak var previous: UIView? = Self.lastClosedView
            let hasPrevious = Self.closeCount > 0
            Self.lastClosedView = view
            Self.closeCount += 1
            Task {
                // 見たいのは初回なら current、2 回目以降なら previous（current はキーボードが握るので待っても解放されない）
                var waited = 0.0
                while waited < 5, hasPrevious ? previous != nil : view != nil {
                    try? await Task.sleep(for: .milliseconds(500))
                    waited += 0.5
                }
                print("TERMINAL view released current=\(view == nil) previous=\(hasPrevious ? String(previous == nil) : "none") after=\(waited)s")
                fflush(stdout)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                print("TERMINAL background")
                fflush(stdout)
                session.enterBackground()
            case .active:
                // 別アプリから戻った・ロック解除した。バックグラウンドでソケットが止められていたかもしれない
                print("TERMINAL foreground")
                fflush(stdout)
                session.enterForeground()  // 記録の消費と生存判定まで一続き
            default:
                break
            }
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
        case .shortcut(let shortcut):
            surface.send(text: shortcut.text)
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
                if case .key = action {
                    print("KEYS pressed \(action.name) appCursor=\(surface.usesApplicationCursorKeys)")
                } else {
                    print("KEYS pressed \(action.name)")
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
        if let resume = LaunchOptions.resumeAfter {
            try? await Task.sleep(for: .seconds(resume.wait))
            // 本番の scenePhase と同じ順（background → foreground）
            session.enterBackground(at: .now - .seconds(resume.background))
            print("TERMINAL resume simulated background=\(Int(resume.background))s")
            fflush(stdout)
            session.enterForeground()
        }
        if let files = LaunchOptions.uploadFiles {
            try? await Task.sleep(for: .seconds(LaunchOptions.uploadAfter))
            let datas = files.compactMap { path -> Data? in
                let data = FileManager.default.contents(atPath: path)
                if data == nil { print("UPLOAD unreadable \(path)") }
                return data
            }
            await attach(datas)
        }
        if let seconds = LaunchOptions.closeAfter {
            try? await Task.sleep(for: .seconds(seconds))
            print("TERMINAL closing")
            fflush(stdout)
            dismiss()
        }
    }

    /// 写真ピッカー / 自走の両方から。変換 → アップロード → 端末に流し込み
    private func attach(_ datas: [Data]) async {
        await attachments.send(datas: datas, session: session, settings: settings, identity: identity, knownHosts: knownHosts)
    }

    /// 上端のバナー。再接続中を優先し、次に画像の送信中
    @ViewBuilder
    private var topBanner: some View {
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
        } else if let progress = attachments.progress {
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction)
                    .frame(width: 80)
                Text("送信中 \(progress.index) / \(progress.total)")
                    .font(.footnote)
                Spacer()
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
        #if DEBUG
        print("TERMINAL wired surface=\(LaunchOptions.objectID(surface)) session=\(LaunchOptions.objectID(session))")
        fflush(stdout)
        #endif
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
