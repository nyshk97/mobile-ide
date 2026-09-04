#!/usr/bin/env swift
// アプリアイコン（案 E「耳モノグラム」）を CoreGraphics で描く。
// PolePole の象の特徴である金の C 型の耳を、青のグラデーション地に置く。
// iOS のアイコンは角丸マスクを OS 側が掛けるので、ここでは全面ベタで出力する。
//
// usage: generate-app-icon.swift <output.png> [size] [light|dark]
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: generate-app-icon.swift <output.png> [size] [light|dark]\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[1]
let size: CGFloat = args.count >= 3 ? CGFloat(Double(args[2]) ?? 1024) : 1024
let variant = args.count >= 4 ? args[3] : "light"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

// SVG モック（y 下向き・1024 基準）と同じ座標をそのまま使えるよう、座標系を反転してスケールする。
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: size / 1024, y: -size / 1024)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// 背景グラデーション（上→下）。dark は同じ青系を沈めた色にして、金の耳は共通。
let (top, bottom): (UInt32, UInt32) = variant == "dark" ? (0x2B3480, 0x161C4A) : (0x7C86E8, 0x3D47B8)
let gradient = CGGradient(colorsSpace: cs, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])

// C 型の耳。中心 (512,512) 半径 230、右側 ±48.4° を開けた弧（SVG: M 700 300 A 230 230 0 1 0 700 724）。
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 230
let openHalfAngle = atan2(212.0, 188.0)  // (700,300) と中心の成す角
let arc = CGMutablePath()
let steps = 180
for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let a = openHalfAngle + t * (2 * .pi - 2 * openHalfAngle)  // 右下の端から左を回って右上の端へ
    let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
}
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
// 紺の縁取り → 金の本体（PolePole の象と同じ塗り分け）
ctx.addPath(arc); ctx.setStrokeColor(rgb(0x0E1440)); ctx.setLineWidth(150); ctx.strokePath()
ctx.addPath(arc); ctx.setStrokeColor(rgb(0xFFD166)); ctx.setLineWidth(96); ctx.strokePath()

// 中心の目（紺の縁 + 白）
ctx.setFillColor(rgb(0x0E1440))
ctx.fillEllipse(in: CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
