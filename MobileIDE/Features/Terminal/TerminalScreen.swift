import SwiftUI

/// 端末画面。サーフェス 1 枚 + キーボードバー + （チャット入力欄モードなら）入力欄 + 接続中 / 切断のオーバーレイ + 再接続中のバナー。
///
/// 入力方式（`InputMode`）は 2 つ。既定のチャット入力欄モードでは入力欄に書いて送信ボタンで PTY に流し（`ComposerMessage`）、
/// 端末は first responder になってもキーボードを出さない（`surface.showsKeyboard = false`）。直接入力モードは従来どおり端末が
/// キーボードを持つ。モードと下書きはプロジェクトごとに `ComposerStore` が記憶する
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
    @State private var store = ComposerStore()
    @State private var composer = ComposerController()
    @State private var inputMode: InputMode = .composer
    @State private var draft = ""
    @State private var wired = false
    @State private var didAutomate = false
    @State private var isTerminalKeyboardVisible = false
    #if DEBUG
    /// 直前に閉じた画面の端末 view。UIKit のキーボードは最後の first responder を 1 個だけ握り続けるので、
    /// 「1 つ前の view が解放されたか」で有界であることを見る（`MOBILE_IDE_OPEN_TIMES=2`）
    private static weak var lastClosedView: UIView?
    private static var closeCount = 0
    #endif

    /// バーのキーボード切替ボタンの見た目。チャット入力欄モードでは入力欄の focus、直接入力モードでは端末のキーボード
    private var isKeyboardVisible: Bool {
        inputMode == .composer ? composer.isFocused : isTerminalKeyboardVisible
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalSurfaceView(surface: surface)
                .overlay { overlay }
                .overlay(alignment: .top) { topBanner }
            KeyboardBar(isKeyboardVisible: isKeyboardVisible, inputMode: inputMode, perform: perform)
            if inputMode == .composer {
                ComposerView(text: $draft, controller: composer, onSend: sendDraft)
            }
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
            isTerminalKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isTerminalKeyboardVisible = false
        }
        .onChange(of: draft) { _, text in
            // 変わるたびに保存する。onDisappear だけだと、閉じた直後に同じプロジェクトを開いたとき（自走の OPEN_TIMES=2 で実測）
            // 新しい画面の onAppear が古い画面の onDisappear より先に走り、空の下書きを読む。UserDefaults の set はメモリ上の更新で安い
            store.setDraft(text, for: target.sessionName)
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

    /// バーの操作。キーと起動系はどちらのモードでも PTY へ（エミュレータ経由の `surface.send` → `onInput`）。
    /// スラッシュコマンドはチャット入力欄モードなら入力欄に挿入する（引数を続けて書ける）
    private func perform(_ action: KeyboardBar.Action) {
        switch action {
        case .key(let key):
            surface.send(bytes: key.bytes(applicationCursor: surface.usesApplicationCursorKeys))
        case .shortcut(let shortcut):
            if case .slash = shortcut, inputMode == .composer {
                insertIntoDraft(shortcut.text)
            } else {
                surface.send(text: shortcut.text)
            }
        case .toggleKeyboard:
            switch inputMode {
            case .composer:
                if composer.isFocused { composer.blur() } else { composer.focus() }
            case .direct:
                if isTerminalKeyboardVisible { surface.hideKeyboard() } else { surface.showKeyboard() }
            }
        case .toggleInputMode:
            setInputMode(inputMode.toggled)
        }
    }

    /// 入力方式を切り替えて記憶する。キーボードは新しい側に渡す（下書きは残す）
    private func setInputMode(_ mode: InputMode) {
        inputMode = mode
        store.setMode(mode, for: target.sessionName)
        print("COMPOSE mode=\(mode.rawValue)")
        fflush(stdout)
        applyInputMode(focus: true)
    }

    /// モードに応じて端末のキーボード可否と focus を揃える
    private func applyInputMode(focus: Bool) {
        switch inputMode {
        case .composer:
            surface.showsKeyboard = false
            surface.hideKeyboard()
            if focus { composer.focus() }
        case .direct:
            composer.blur()
            surface.showsKeyboard = true
            if focus { surface.showKeyboard() }
        }
    }

    /// 入力欄のカーソル位置に差し込む（スラッシュコマンド・画像のパス）
    private func insertIntoDraft(_ text: String) {
        composer.insert(text, into: &draft)
        print("COMPOSE inserted \(text)")
        fflush(stdout)
    }

    /// 送信ボタン。未確定文字を確定 → `ComposerMessage` で包んで PTY へ → 入力欄を空に。切断中は送らず下書きを残す
    private func sendDraft() {
        composer.commitMarkedText()
        let data = ComposerMessage.bytes(for: draft)
        guard !data.isEmpty else { return }
        guard session.state == .running else {
            attachments.alert = AttachmentFlow.Alert(title: "端末に接続していません", message: "接続が戻ったらもう一度送ってください。下書きは残しています。")
            return
        }
        session.send(data)
        print("COMPOSE sent bytes=\(data.count)")
        fflush(stdout)
        draft = ""  // onChange で保存も空になる
    }

    /// 自走検証: MOBILE_IDE_TERMINAL_TYPE の送信、MOBILE_IDE_PRESS_KEYS のバー操作の再現、MOBILE_IDE_DRAFT / MOBILE_IDE_COMPOSE の
    /// 入力欄操作、MOBILE_IDE_PROBE_AFTER の生存判定。最初に running になったときだけ走る（再接続のたびに文字列を送り直さない）
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
        if let text = LaunchOptions.draftText {
            try? await Task.sleep(for: .milliseconds(500))
            insertIntoDraft(text)
            print("COMPOSE draft set n=\(draft.count)")
            fflush(stdout)
        }
        if let text = LaunchOptions.composeText {
            try? await Task.sleep(for: .seconds(LaunchOptions.composeAfter))
            insertIntoDraft(text)
            sendDraft()
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

    /// 写真ピッカー / 自走の両方から。変換 → アップロード → パスの流し込み。
    /// 流し込み先はモードで分ける: チャット入力欄なら接続状態に関係なく入力欄へ、直接入力なら running のときだけ端末へ
    private func attach(_ datas: [Data]) async {
        // 直接入力モードは端末に打ち込むので接続が要る。チャット入力欄モードは切断中でも入力欄に挿せる（アップロードは別接続）
        if inputMode == .direct, session.state != .running {
            attachments.alert = AttachmentFlow.Alert(title: "端末に接続してから選んでください", message: "接続が戻ったらもう一度選んでください。")
            return
        }
        await attachments.send(datas: datas, session: session, settings: settings, identity: identity, knownHosts: knownHosts) { text in
            switch inputMode {
            case .composer:
                insertIntoDraft(text)
                return true
            case .direct:
                guard session.state == .running else { return false }
                session.send(Data(text.utf8))
                return true
            }
        }
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
        // モードと下書きの復元。MOBILE_IDE_INPUT_MODE は上書きだけで保存しない（保存 → 復元の経路は付けずに開き直して見る）
        inputMode = LaunchOptions.inputModeOverride ?? store.mode(for: target.sessionName)
        draft = store.draft(for: target.sessionName)
        print("COMPOSE mode=\(inputMode.rawValue)")
        if !draft.isEmpty { print("COMPOSE draft restored n=\(draft.count)") }
        fflush(stdout)
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
        DispatchQueue.main.async { applyInputMode(focus: true) }
    }

    private func start(size: TerminalSize? = nil) {
        guard let size = size ?? surface.currentSize else { return }
        let settings = settings, identity = identity, knownHosts = knownHosts
        session.start(target: target, size: size) {
            try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        }
    }
}
