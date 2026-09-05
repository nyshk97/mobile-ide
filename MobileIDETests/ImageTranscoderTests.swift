import UIKit
import XCTest
@testable import MobileIDE

final class ImageTranscoderTests: XCTestCase {
    private func image(width: Int, height: Int, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = 1
            return f
        }()).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func size(of data: Data) -> (Int, Int) {
        let image = UIImage(data: data)!
        return (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    func testLargeJPEGIsScaledToMaxPixelSize() throws {
        let jpeg = image(width: 4000, height: 3000, color: .yellow).jpegData(compressionQuality: 0.9)!
        let item = try ImageTranscoder.transcode(jpeg)
        XCTAssertEqual(item.ext, "jpg")
        XCTAssertEqual(size(of: item.data).0, 2048)
        XCTAssertEqual(size(of: item.data).1, 1536)
        XCTAssertEqual(item.data.prefix(2), Data([0xFF, 0xD8]))  // JPEG SOI
    }

    func testSmallImageKeepsSize() throws {
        let jpeg = image(width: 1000, height: 500, color: .red).jpegData(compressionQuality: 0.9)!
        let item = try ImageTranscoder.transcode(jpeg)
        XCTAssertEqual(size(of: item.data).0, 1000)
        XCTAssertEqual(size(of: item.data).1, 500)
    }

    func testPNGStaysPNGAndIsScaled() throws {
        let png = image(width: 1200, height: 2600, color: .white).pngData()!
        let item = try ImageTranscoder.transcode(png)
        XCTAssertEqual(item.ext, "png")
        XCTAssertEqual(item.data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(size(of: item.data).0, 945)
        XCTAssertEqual(size(of: item.data).1, 2048)
    }

    func testUndecodableDataThrows() {
        XCTAssertThrowsError(try ImageTranscoder.transcode(Data("not an image".utf8)))
    }
}

final class UploadNameTests: XCTestCase {
    func testFormatAndSequence() {
        let now = Date(timeIntervalSince1970: 1_788_600_000)  // 2026-09-05 18:20:00 JST
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(UploadName.make(ext: "jpg", now: now, index: 1, timeZone: tz), "20260905-182000-1.jpg")
        XCTAssertEqual(UploadName.make(ext: "png", now: now, index: 2, timeZone: tz), "20260905-182000-2.png")
        XCTAssertNotEqual(UploadName.make(ext: "jpg", now: now, index: 1, timeZone: tz), UploadName.make(ext: "jpg", now: now, index: 2, timeZone: tz))
    }
}
