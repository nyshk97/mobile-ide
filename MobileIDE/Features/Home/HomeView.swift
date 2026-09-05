import SwiftUI

/// 最初の画面。PolePole のプロジェクト一覧（ピン留め + その他）と、タップで tmux セッションへ。
struct HomeView: View {
    enum Route: Hashable {
        case terminal(TerminalTarget)
        case settings
    }

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts

    @State private var model = ProjectListModel()
    /// 自走検証（MOBILE_IDE_TERMINAL_AUTORUN / MOBILE_IDE_CONNECTION_TEST）のときは該当画面を最初から開く
    @State private var path: [Route] = LaunchOptions.terminalAutorun ? [.terminal(.mobileIDE)]
        : LaunchOptions.connectionTest ? [.settings] : []
    @State private var autoOpenCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !settings.isConfigured {
                    Section {
                        NavigationLink(value: Route.settings) {
                            Label("右上の歯車から接続先を設定し、公開鍵を Mac に登録してください", systemImage: "gear")
                                .font(.footnote)
                        }
                    }
                } else {
                    statusSection
                    if !model.pinned.isEmpty {
                        Section("ピン留め") {
                            ForEach(model.pinned) { row in rowLink(row) }
                        }
                    }
                    if !model.others.isEmpty {
                        Section("その他") {
                            ForEach(model.others) { row in rowLink(row) }
                        }
                    }
                }
            }
            .navigationTitle("Mobile IDE")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .terminal(let target): TerminalScreen(target: target)
                case .settings: SettingsScreen()
                }
            }
            .toolbar {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("設定")
            }
            .refreshable { await refresh() }
        }
        .task(id: settings.isConfigured) {
            // 自走検証が authorized_keys に登録できるよう、起動時に公開鍵行を stdout に出す
            settings.saveLaunchOverridesIfRequested()
            print("SSH pubkey \(identity.publicKeyLine)")
            #if DEBUG
            print("HOME settings host=\(settings.host) port=\(settings.port) user=\(settings.user) configured=\(settings.isConfigured)")
            #endif
            if settings.isConfigured { await refresh() }
        }
        .onChange(of: path) { old, new in
            // 端末から一覧に戻ったらセッションの印を更新する
            if !old.isEmpty, new.isEmpty, settings.isConfigured {
                Task { await refresh() }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.phase {
        case .idle, .loading:
            if model.isEmpty {
                Section { HStack { ProgressView(); Text("プロジェクトを読み込み中…").foregroundStyle(.secondary) } }
            }
        case .failed(let failure):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        {
                            if case .hostKeyMismatch = failure { return "ホスト鍵が変わりました" }
                            return "一覧を取得できませんでした"
                        }(),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                    Text(failure.description)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("再試行") { Task { await refresh() } }
                            .buttonStyle(.bordered)
                        if case .hostKeyMismatch = failure {
                            NavigationLink("設定で確認", value: Route.settings)
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        case .loaded:
            if model.isEmpty {
                Section {
                    Text("PolePole にプロジェクトがありません。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rowLink(_ row: ProjectListModel.Row) -> some View {
        NavigationLink(value: Route.terminal(row.target)) {
            ProjectRowView(row: row, homePath: "/Users/\(settings.user)")
        }
    }

    private func refresh() async {
        await model.refresh(settings: settings, identity: identity, knownHosts: knownHosts)
        // 自走検証: MOBILE_IDE_OPEN_PROJECT=<sessionName> の行を自動で開く
        if autoOpenCount < LaunchOptions.openProjectTimes, let name = LaunchOptions.openProject,
           let row = model.allRows.first(where: { $0.sessionName == name }) {
            autoOpenCount += 1
            path.append(.terminal(row.target))
        }
    }
}

#Preview {
    HomeView()
        .environment(ConnectionSettings())
        .environment(SSHIdentity(store: InMemorySSHKeyStore()))
        .environment(KnownHostStore())
}
