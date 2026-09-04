import SwiftUI

@main
struct MobileIDEApp: App {
    @State private var settings = ConnectionSettings()
    @State private var identity = SSHIdentity()
    @State private var knownHosts = KnownHostStore()

    init() {
        // 自走検証は simctl / devicectl の --console で stdout を読む。パイプ相手だと全バッファになり
        // 目印行が届かないことがあるので無バッファにする
        setvbuf(stdout, nil, _IONBF, 0)
        // 自走検証用（DEBUG のみ）: ホスト鍵の記録を起動時に消す / 差し替える
        if let override = LaunchOptions.knownHostOverride {
            switch override {
            case .forget:
                knownHosts.remove(host: settings.host, port: settings.port)
                print("SSH knownhost forgotten \(settings.host):\(settings.port)")
            case .replace(let line):
                knownHosts.set(line, host: settings.host, port: settings.port)
                print("SSH knownhost replaced \(settings.host):\(settings.port)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(settings)
                .environment(identity)
                .environment(knownHosts)
        }
    }
}
