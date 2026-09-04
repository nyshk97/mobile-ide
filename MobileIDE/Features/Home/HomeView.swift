import SwiftUI

/// 最初の画面。#3 では固定の tmux セッション（mobile-ide）を開く行だけ。プロジェクト一覧は #5。
struct HomeView: View {
    enum Route: Hashable {
        case terminal
        case settings
    }

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity

    /// 自走検証（MOBILE_IDE_TERMINAL_AUTORUN / MOBILE_IDE_CONNECTION_TEST）のときは該当画面を最初から開く
    @State private var path: [Route] = LaunchOptions.terminalAutorun ? [.terminal]
        : LaunchOptions.connectionTest ? [.settings] : []

    private let target = TerminalTarget.mobileIDE

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("プロジェクト") {
                    NavigationLink(value: Route.terminal) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(target.sessionName)
                                Text(settings.isConfigured
                                     ? "\(settings.user)@\(settings.host) \(target.workingDirectory)"
                                     : "接続先が未設定です")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "terminal")
                        }
                    }
                    .disabled(!settings.isConfigured)
                }
                if !settings.isConfigured {
                    Section {
                        NavigationLink(value: Route.settings) {
                            Label("右上の歯車から接続先を設定し、公開鍵を Mac に登録してください", systemImage: "gear")
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Mobile IDE")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .terminal: TerminalScreen(target: target)
                case .settings: SettingsScreen()
                }
            }
            .toolbar {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("設定")
            }
        }
        .task {
            // 自走検証が authorized_keys に登録できるよう、起動時に公開鍵行を stdout に出す
            print("SSH pubkey \(identity.publicKeyLine)")
        }
    }
}

#Preview {
    HomeView()
        .environment(ConnectionSettings())
        .environment(SSHIdentity(store: InMemorySSHKeyStore()))
        .environment(KnownHostStore())
}
