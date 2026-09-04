import SwiftUI

/// `TerminalSurface` の UIView を SwiftUI に載せるだけの薄いラッパー。
/// surface の寿命は画面側（`TerminalScreen`）が持つので、ここでは生成も破棄もしない。
struct TerminalSurfaceView: UIViewRepresentable {
    let surface: any TerminalSurface

    func makeUIView(context: Context) -> UIView {
        surface.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
