import SwiftUI

@main
struct MobileIDEApp: App {
    init() {
        // 自走検証は simctl / devicectl の --console で stdout を読む。パイプ相手だと全バッファになり
        // 目印行が届かないことがあるので無バッファにする
        setvbuf(stdout, nil, _IONBF, 0)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
