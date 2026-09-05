import UIKit
import XCTest
@testable import MobileIDE

/// DECCKM（アプリケーションカーソルモード）の追跡。tmux はペイン側の `ESC c`（RIS）や DECCKM を自分で解釈して
/// クライアントに `ESC [ ? 1 h/l` を送り直すので、RIS の経路は tmux 越しの自走では見えない。ここで surface に直接 feed する
@MainActor
final class SwiftTermSurfaceTests: XCTestCase {
    private func makeSurface() -> SwiftTermSurface {
        let surface = SwiftTermSurface()
        // frame が .zero のままだと桁数 0 で feed することになるので、レイアウトを一度通す
        surface.view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        surface.view.layoutIfNeeded()
        XCTAssertNotNil(surface.currentSize)
        return surface
    }

    private func feed(_ surface: SwiftTermSurface, _ text: String) {
        surface.feed(ArraySlice(Array(text.utf8)))
    }

    func testDECCKMOnThenOff() {
        let surface = makeSurface()
        XCTAssertFalse(surface.usesApplicationCursorKeys)
        feed(surface, "\u{1b}[?1h")
        XCTAssertTrue(surface.usesApplicationCursorKeys)
        // 初期値と同じ false なので、オンにしてから見ないと何も feed せずに通ってしまう
        feed(surface, "\u{1b}[?1l")
        XCTAssertFalse(surface.usesApplicationCursorKeys)
    }

    func testRISResetsApplicationCursor() {
        let surface = makeSurface()
        feed(surface, "\u{1b}[?1h")
        XCTAssertTrue(surface.usesApplicationCursorKeys)
        feed(surface, "\u{1b}c")  // RIS。エミュレータがモードを初期化する
        XCTAssertFalse(surface.usesApplicationCursorKeys)
    }

    func testSequenceSplitAcrossChunks() {
        let surface = makeSurface()
        feed(surface, "\u{1b}[?")
        feed(surface, "1h")
        XCTAssertTrue(surface.usesApplicationCursorKeys)
    }
}
