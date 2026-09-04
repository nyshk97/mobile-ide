import Foundation
import SwiftTerm
import UIKit

/// `TerminalSurface` の SwiftTerm 実装。`TerminalView` を 1 枚持ち、そのデリゲートになる。
@MainActor
final class SwiftTermSurface: NSObject, TerminalSurface {
    private let terminalView: TerminalView

    private(set) var currentSize: TerminalSize?
    var onInput: ((Data) -> Void)?
    var onResize: ((TerminalSize) -> Void)?

    var view: UIView { terminalView }

    override init() {
        terminalView = TerminalView(frame: .zero, font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        super.init()
        terminalView.terminalDelegate = self
        terminalView.nativeBackgroundColor = .systemBackground
        terminalView.nativeForegroundColor = .label
        // 既定の inputAccessoryView（TerminalAccessory: esc / ctrl / tab / 矢印）はそのまま使う。自前バーは #6
    }

    func feed(_ bytes: ArraySlice<UInt8>) {
        terminalView.feed(byteArray: bytes)
    }

    func focus() {
        terminalView.becomeFirstResponder()
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
