import SwiftUI

/// 最初の画面。まだ接続機能は無く、体裁を整えるためのプレースホルダ。
struct HomeView: View {
    /// 自走検証（MOBILE_IDE_SPIKE_AUTORUN=1）のときはスパイク画面を最初から開く
    @State private var path: [SpikeRoute] = SpikeAutorun.isRequested ? [.spike] : []

    var body: some View {
        NavigationStack(path: $path) {
            ContentUnavailableView(
                "接続先が未設定です",
                systemImage: "desktopcomputer.and.arrow.down",
                description: Text("Mac mini への SSH 接続はこれから実装します。")
            )
            .navigationTitle("Mobile IDE")
            #if DEBUG
            .toolbar {
                // #2 のスパイク画面への導線。#4 で接続設定画面ができたら消す
                NavigationLink("SSH スパイク", value: SpikeRoute.spike)
            }
            .navigationDestination(for: SpikeRoute.self) { _ in SSHSpikeView() }
            #endif
        }
        .task { SpikeAutorun.printPublicKey() }
    }
}

enum SpikeRoute: Hashable {
    case spike
}

#Preview {
    HomeView()
}
