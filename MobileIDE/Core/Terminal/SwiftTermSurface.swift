import Foundation
import SwiftTerm
import UIKit

/// `TerminalSurface` の SwiftTerm 実装。`TerminalView` を 1 枚持ち、そのデリゲートになる。
@MainActor
final class SwiftTermSurface: NSObject, TerminalSurface {
    /// テストから直接触るので internal。`WheelScrollingTerminalView` はマウス追跡中の一本指ドラッグをホイールに変える差し込み（#14 で消す）
    let terminalView: WheelScrollingTerminalView

    private(set) var currentSize: TerminalSize?
    var onInput: ((Data) -> Void)?
    var onResize: ((TerminalSize) -> Void)?
    private var isTornDown = false

    var view: UIView { terminalView }

    /// DECCKM はエミュレータ自身の状態を読む（`getTerminal()` と `Terminal.applicationCursor` は public。
    /// `feed` は同期にパースするので feed 直後に最新）。RIS（`ESC c`）などで戻る経路も自動で追従する
    var usesApplicationCursorKeys: Bool { terminalView.getTerminal().applicationCursor }

    override init() {
        terminalView = WheelScrollingTerminalView(frame: .zero, font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        super.init()
        terminalView.terminalDelegate = self
        terminalView.nativeBackgroundColor = .systemBackground
        terminalView.nativeForegroundColor = .label
        // 既定の inputAccessoryView（esc / ctrl / tab / 矢印）は外し、端末の下に常駐する自前のバー（KeyboardBar）を使う
        terminalView.inputAccessoryView = nil
    }

    #if DEBUG
    deinit {
        print("TERMINAL surface deinit \(LaunchOptions.objectID(self))")
        fflush(stdout)
    }
    #endif

    func tearDown() {
        isTornDown = true
        onInput = nil
        onResize = nil
        _ = terminalView.resignFirstResponder()
        terminalView.updateUiClosed()
    }

    func feed(_ bytes: ArraySlice<UInt8>) {
        // tearDown 後は描画タイマーが止まっているので捨てる（onOutput は画面側で外しているが、契約として守る）
        guard !isTornDown else {
            print("TERMINAL surface fed after tearDown \(LaunchOptions.objectID(self))")
            fflush(stdout)
            return
        }
        terminalView.feed(byteArray: bytes)
    }

    func send(bytes: [UInt8]) {
        terminalView.send(bytes)
    }

    func send(text: String) {
        terminalView.send(txt: text)
    }

    func showKeyboard() {
        _ = terminalView.becomeFirstResponder()
    }

    func hideKeyboard() {
        _ = terminalView.resignFirstResponder()
    }
}

extension SwiftTermSurface: TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let size = TerminalSize(cols: newCols, rows: newRows)
        guard size != currentSize else { return }
        currentSize = size
        print("TERMINAL size \(newCols)x\(newRows)")
        fflush(stdout)
        onResize?(size)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(decoding: content, as: UTF8.self)
    }
    func clipboardRead(source: TerminalView) -> Data? {
        UIPasteboard.general.string.map { Data($0.utf8) }
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
