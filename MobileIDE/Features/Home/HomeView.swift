import SwiftUI

/// 最初の画面。#3 では固定の tmux セッション（mobile-ide）を開くボタンだけ。プロジェクト一覧は #5。
struct HomeView: View {
    enum Route: Hashable {
        case terminal
        case spike
    }

    /// 自走検証（MOBILE_IDE_TERMINAL_AUTORUN / MOBILE_IDE_SPIKE_AUTORUN）のときは該当画面を最初から開く
    @State private var path: [Route] = TerminalAutorun.isRequested ? [.terminal]
        : SpikeAutorun.isRequested ? [.spike] : []

    private let target = TerminalTarget.current()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("プロジェクト") {
                    NavigationLink(value: Route.terminal) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(target.sessionName)
                                Text("\(target.user)@\(target.host) \(target.workingDirectory)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "terminal")
                        }
                    }
                    .disabled(target.user.isEmpty)
                }
                if target.user.isEmpty {
                    Section {
                        Text("接続先が未設定です。右上の「SSH スパイク」でホスト名・ユーザー名を入れ、公開鍵を登録してください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mobile IDE")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .terminal: TerminalScreen(target: target)
                case .spike: SSHSpikeView()
                }
            }
            #if DEBUG
            .toolbar {
                // #2 のスパイク画面への導線。#4 で接続設定画面ができたら消す
                NavigationLink("SSH スパイク", value: Route.spike)
            }
            #endif
        }
        .task { SpikeAutorun.printPublicKey() }
    }
}

#Preview {
    HomeView()
}
