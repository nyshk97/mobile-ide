import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ホストに置く 1 枚。`ext` は `jpg` か `png`
struct UploadItem: Sendable {
    var data: Data
    var ext: String
}

enum ImageTranscodeError: Error, CustomStringConvertible {
    case undecodable
    case encodeFailed

    var description: String {
        switch self {
        case .undecodable: return "画像として読めませんでした"
        case .encodeFailed: return "画像の変換に失敗しました"
        }
    }
}

/// 写真ピッカーの元データ（HEIC / JPEG / PNG）を、Claude Code が読める形に整える。
///
/// - 長辺 2048px を超えていれば縮小（EXIF の向きも正規化）
/// - PNG（スクショ）は PNG のまま、それ以外は JPEG 品質 0.85
/// - PNG かどうかはピッカーの型情報でなくデータ自身（`CGImageSourceGetType`）で判定する
///
/// MainActor に縛らない純関数。12MP を 4 枚も回すと数百 ms かかるので `Task.detached` から呼ぶ
enum ImageTranscoder {
    static let maxPixelSize = 2048
    static let jpegQuality = 0.85

    nonisolated static func transcode(_ data: Data) throws -> UploadItem {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImageTranscodeError.undecodable
        }
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageTranscodeError.undecodable
        }
        let type = isPNG ? UTType.png : UTType.jpeg
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else {
            throw ImageTranscodeError.encodeFailed
        }
        var properties: [CFString: Any] = [:]
        if !isPNG { properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageTranscodeError.encodeFailed }
        return UploadItem(data: out as Data, ext: isPNG ? "png" : "jpg")
    }
}
