import SwiftUI

/// キーボードバーの起動系ボタンのマーク。Claude / Codex / git のロゴは SF Symbols に無いので SwiftUI で描く。
/// どれも 20pt 角に収まる比率（`frame` は呼び出し側）。

/// Clawd 風のピクセル絵（胴体 + 目 + 手足）。オレンジ
struct ClaudeMark: View {
    var body: some View {
        Canvas { context, size in
            let u = size.width / 24
            let color = Color(red: 0.85, green: 0.47, blue: 0.34)
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: Color) {
                let path = Path(roundedRect: CGRect(x: x * u, y: y * u, width: w * u, height: h * u), cornerRadius: r * u)
                context.fill(path, with: .color(fill))
            }
            rect(5, 5, 14, 12, 3.5, color)          // 胴体
            rect(8.5, 9, 2.2, 3, 0.6, .black)       // 目
            rect(13.3, 9, 2.2, 3, 0.6, .black)
            rect(7, 17, 2.5, 3, 1, color)           // 足
            rect(14.5, 17, 2.5, 3, 1, color)
            rect(2.5, 9, 2.5, 5, 1, color)          // 手
            rect(19, 9, 2.5, 5, 1, color)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 六角形の結び目（前景色の線）
struct CodexMark: View {
    var body: some View {
        Canvas { context, size in
            let u = size.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            var path = Path()
            path.move(to: p(12, 3.2))
            for point in [p(19.6, 7.6), p(19.6, 16.4), p(12, 20.8), p(4.4, 16.4), p(4.4, 7.6)] { path.addLine(to: point) }
            path.closeSubpath()
            path.move(to: p(12, 3.2)); path.addLine(to: p(12, 12))
            path.move(to: p(4.4, 7.6)); path.addLine(to: p(12, 12)); path.addLine(to: p(19.6, 7.6))
            path.move(to: p(12, 12)); path.addLine(to: p(12, 20.8))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.7 * u, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// git のブランチ図（点 3 つと線）。赤
struct GitMark: View {
    var body: some View {
        Canvas { context, size in
            let u = size.width / 24
            let color = Color(red: 0.94, green: 0.32, blue: 0.2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            var lines = Path()
            lines.move(to: p(7, 7.7)); lines.addLine(to: p(7, 16.3))
            lines.move(to: p(17, 11.7))
            lines.addCurve(to: p(7, 18.3), control1: p(17, 15.3), control2: p(12, 15.5))
            context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round))
            for center in [p(7, 5.5), p(7, 18.5), p(17, 9.5)] {
                let circle = Path(ellipseIn: CGRect(x: center.x - 2.2 * u, y: center.y - 2.2 * u, width: 4.4 * u, height: 4.4 * u))
                context.stroke(circle, with: .color(color), lineWidth: 1.8 * u)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    HStack(spacing: 20) {
        ClaudeMark().frame(width: 20)
        CodexMark().frame(width: 20)
        GitMark().frame(width: 20)
    }
    .padding()
}
