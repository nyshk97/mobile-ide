// 画像添付（#8）の検証用に、Claude の答えで判別できる合成画像を作る。
// 使い方: swift scripts/make-test-images.swift <出力ディレクトリ>
//   → <dir>/mobile-ide-test.jpg  4000x3000 の JPEG（黄色地に赤い「MOBILE IDE JPEG」と青い丸）
//   → <dir>/mobile-ide-test.png  1200x2600 の PNG（白地に黒い「MOBILE IDE PNG」と緑の四角。スクショ想定）
import AppKit
import Foundation

func draw(size: CGSize, background: NSColor, text: String, textColor: NSColor, shape: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    background.setFill()
    CGRect(origin: .zero, size: size).fill()
    shape(ctx.cgContext)
    let font = NSFont.boldSystemFont(ofSize: size.width / 12)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
    let str = NSAttributedString(string: text, attributes: attrs)
    let textSize = str.size()
    str.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

let jpeg = draw(size: CGSize(width: 4000, height: 3000), background: .yellow, text: "MOBILE IDE JPEG", textColor: .red) { cg in
    cg.setFillColor(NSColor.blue.cgColor)
    cg.fillEllipse(in: CGRect(x: 300, y: 300, width: 900, height: 900))
}
try! jpeg.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: "\(dir)/mobile-ide-test.jpg"))

let png = draw(size: CGSize(width: 1200, height: 2600), background: .white, text: "MOBILE IDE PNG", textColor: .black) { cg in
    cg.setFillColor(NSColor.green.cgColor)
    cg.fill(CGRect(x: 200, y: 1800, width: 800, height: 500))
}
try! png.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/mobile-ide-test.png"))
print("wrote \(dir)/mobile-ide-test.jpg and \(dir)/mobile-ide-test.png")
