import UIKit
import XCTest
@testable import MobileIDE

/// マウス追跡中の一本指ドラッグ → ホイール報告（`WheelScrollingTerminalView`）。
/// ジェスチャーそのものは合成できないので、ジェスチャーハンドラが呼ぶ `reportWheel` を直接叩き、
/// 端末が送るバイト列（SGR: `ESC [ < 64|65 ; col ; row M`）を `onInput` で受けて見る
@MainActor
final class WheelScrollingTerminalViewTests: XCTestCase {
    private var surface: SwiftTermSurface!
    private var sent: [UInt8] = []

    override func setUp() {
        super.setUp()
        surface = SwiftTermSurface()
        surface.view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        surface.view.layoutIfNeeded()
        XCTAssertNotNil(surface.currentSize)
        sent = []
        surface.onInput = { [unowned self] data in self.sent += data }
    }

    private var view: WheelScrollingTerminalView { surface.terminalView }

    private func feed(_ text: String) {
        surface.feed(ArraySlice(Array(text.utf8)))
    }

    /// VT200 のボタン追跡 + SGR 符号化（Claude Code が使う組み合わせ）
    private func enableMouseTracking() {
        feed("\u{1b}[?1000h\u{1b}[?1006h")
    }

    private func sentText() -> String { String(decoding: sent, as: UTF8.self) }

    func testMouseModeSwitchesOneFingerToWheelAndTwoFingersToScroll() {
        XCTAssertFalse(view.mouseTrackingActive)
        XCTAssertEqual(view.panGestureRecognizer.minimumNumberOfTouches, 1)
        enableMouseTracking()
        XCTAssertTrue(view.mouseTrackingActive)
        XCTAssertEqual(view.panGestureRecognizer.minimumNumberOfTouches, 2)
        feed("\u{1b}[?1000l")
        XCTAssertFalse(view.mouseTrackingActive, "追跡が切れたら SwiftTerm 側の一本指スクロールに戻す")
        XCTAssertEqual(view.panGestureRecognizer.minimumNumberOfTouches, 1)
    }

    func testDragDownSendsWheelUpPerCellRow() {
        enableMouseTracking()
        let h = view.cellHeight
        XCTAssertGreaterThan(h, 0)
        // 3 行と少し下に動かす。位置は左端（col 0 → 1）・5 行目（row 5 → 6）
        let lines = view.reportWheel(distance: 3 * h + 1, at: CGPoint(x: 0, y: 5 * h + 0.5))
        XCTAssertEqual(lines, 3)
        XCTAssertEqual(sentText(), String(repeating: "\u{1b}[<64;1;6M", count: 3))
    }

    func testDragUpSendsWheelDown() {
        enableMouseTracking()
        let h = view.cellHeight
        let lines = view.reportWheel(distance: -2 * h, at: CGPoint(x: 0, y: 0))
        XCTAssertEqual(lines, -2)
        XCTAssertEqual(sentText(), String(repeating: "\u{1b}[<65;1;1M", count: 2))
    }

    func testSubCellMovesAccumulate() {
        enableMouseTracking()
        let h = view.cellHeight
        XCTAssertEqual(view.reportWheel(distance: 0.6 * h, at: .zero), 0)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(view.reportWheel(distance: 0.6 * h, at: .zero), 1, "端数を持ち越して 1.2 行で 1 報告")
        XCTAssertEqual(sentText(), "\u{1b}[<64;1;1M")
    }

    func testReportsPerEventAreCapped() {
        enableMouseTracking()
        let h = view.cellHeight
        let lines = view.reportWheel(distance: 10 * h, at: .zero)
        XCTAssertEqual(lines, WheelScrollingTerminalView.maxReportsPerEvent)
        XCTAssertEqual(sent.count, "\u{1b}[<64;1;1M".utf8.count * WheelScrollingTerminalView.maxReportsPerEvent)
    }

    func testUnfocusedTapForwardsClickWithoutFocusing() {
        enableMouseTracking()
        XCTAssertTrue(view.hasUnfocusedClickRecognizer)
        XCTAssertFalse(view.isFirstResponder)
        XCTAssertTrue(view.shouldForwardUnfocusedTap, "追跡中でフォーカスが無ければ SwiftTerm の singleTap でなくクリック転送")
        let h = view.cellHeight
        XCTAssertTrue(view.forwardClick(at: CGPoint(x: 0, y: 5 * h + 0.5)))
        XCTAssertEqual(sentText(), "\u{1b}[<0;1;6M\u{1b}[<0;1;6m", "左ボタンの押下と解放")
        XCTAssertFalse(view.isFirstResponder, "キーボードは出さない")
    }

    func testUnfocusedTapIsLeftToSwiftTermWithoutMouseTracking() {
        XCTAssertFalse(view.shouldForwardUnfocusedTap)
        XCTAssertFalse(view.forwardClick(at: .zero))
        XCTAssertTrue(sent.isEmpty)
        enableMouseTracking()
        feed("\u{1b}[?1000l")
        XCTAssertFalse(view.shouldForwardUnfocusedTap, "追跡が切れたら singleTap（becomeFirstResponder）に戻す")
        XCTAssertTrue(view.hasUnfocusedClickRecognizer, "recognizer は常設で、条件で失敗させる")
    }

    /// `cellHeight` / `cellWidth` は SwiftTerm の `computeFontDimensions` を写しているので、SwiftTerm が決めた行数・桁数と突き合わせる
    func testCellDimensionsMatchSwiftTermGrid() {
        let size = surface.currentSize!
        XCTAssertEqual(Int(view.bounds.height / view.cellHeight), size.rows)
        XCTAssertEqual(Int(view.bounds.width / view.cellWidth), size.cols)
    }

    func testNothingIsSentWithoutMouseTracking() {
        let h = view.cellHeight
        XCTAssertEqual(view.reportWheel(distance: 5 * h, at: .zero), 0)
        XCTAssertTrue(sent.isEmpty)
    }
}
