import SwiftUI

/// 最初の画面。まだ接続機能は無く、体裁を整えるためのプレースホルダ。
struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "接続先が未設定です",
                systemImage: "desktopcomputer.and.arrow.down",
                description: Text("Mac mini への SSH 接続はこれから実装します。")
            )
            .navigationTitle("Mobile IDE")
        }
    }
}

#Preview {
    HomeView()
}
