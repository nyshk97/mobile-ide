import XCTest
@testable import MobileIDE

final class ComposerMessageTests: XCTestCase {
    private let start = "\u{1b}[200~"
    private let end = "\u{1b}[201~"

    private func string(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    func testSingleLineIsWrappedAndEnterIsOutside() {
        XCTAssertEqual(string(ComposerMessage.bytes(for: "hello")), start + "hello" + end + "\r")
    }

    func testNewlinesBecomeCarriageReturns() {
        XCTAssertEqual(string(ComposerMessage.bytes(for: "a\nb\nc")), start + "a\rb\rc" + end + "\r")
        XCTAssertEqual(string(ComposerMessage.bytes(for: "a\r\nb")), start + "a\rb" + end + "\r", "CRLF は 1 つの CR")
        XCTAssertEqual(string(ComposerMessage.bytes(for: "a\rb")), start + "a\rb" + end + "\r")
    }

    func testTrailingNewlinesAreDropped() {
        XCTAssertEqual(string(ComposerMessage.bytes(for: "a\n")), start + "a" + end + "\r")
        XCTAssertEqual(string(ComposerMessage.bytes(for: "a\n\n\r\n")), start + "a" + end + "\r")
        XCTAssertEqual(string(ComposerMessage.bytes(for: "\n\na\nb")), start + "\r\ra\rb" + end + "\r", "先頭の改行は残す")
    }

    func testEscapeIsRemoved() {
        // 本文に ESC[201~ があると包みを途中で閉じられる。ESC だけ落として残りは文字として通す
        XCTAssertEqual(string(ComposerMessage.bytes(for: "x\u{1b}[201~y")), start + "x[201~y" + end + "\r")
        XCTAssertEqual(string(ComposerMessage.bytes(for: "\u{1b}\u{1b}")), "", "ESC だけなら空")
    }

    func testEmptyBodySendsNothing() {
        XCTAssertEqual(ComposerMessage.bytes(for: ""), Data())
        XCTAssertEqual(ComposerMessage.bytes(for: "\n\n"), Data())
        XCTAssertEqual(ComposerMessage.bytes(for: "\r\n"), Data())
    }

    func testMultibyteTextPassesThrough() {
        XCTAssertEqual(string(ComposerMessage.bytes(for: "日本語\n2 行目")), start + "日本語\r2 行目" + end + "\r")
    }
}
