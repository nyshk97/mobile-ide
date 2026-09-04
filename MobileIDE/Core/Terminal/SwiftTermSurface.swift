import Foundation
import SwiftTerm
import UIKit

/// `TerminalSurface` の SwiftTerm 実装。`TerminalView` を 1 枚持ち、そのデリゲートになる。
@MainActor
final class SwiftTermSurface: NSObject, TerminalSurface {
    private let terminalView: TerminalView
    private var controlResetObserver: NSObjectProtocol?

    private(set) var currentSize: TerminalSize?
    var onInput: ((Data) -> Void)?
    var onResize: ((TerminalSize) -> Void)?
    var onControlReset: (() -> Void)?

    var view: UIView { terminalView }

    /// SwiftTerm 1.20 は Terminal（applicationCursor）を public に出していないので、
    /// ホストからの出力に含まれる DECCKM（`ESC [ ? 1 h` / `ESC [ ? 1 l`）を自前で追跡する
    private(set) var usesApplicationCursorKeys = false
    private var feedTail: [UInt8] = []

    override init() {
        terminalView = TerminalView(frame: .zero, font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        super.init()
        terminalView.terminalDelegate = self
        terminalView.nativeBackgroundColor = .systemBackground
        terminalView.nativeForegroundColor = .label
        // 既定の inputAccessoryView（esc / ctrl / tab / 矢印）は外し、端末の下に常駐する自前のバー（KeyboardBar）を使う
        terminalView.inputAccessoryView = nil
        controlResetObserver = NotificationCenter.default.addObserver(
            forName: .terminalViewControlModifierReset,
            object: terminalView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onControlReset?() }
        }
    }

    deinit {
        if let controlResetObserver { NotificationCenter.default.removeObserver(controlResetObserver) }
    }

    func feed(_ bytes: ArraySlice<UInt8>) {
        trackCursorKeyMode(bytes)
        terminalView.feed(byteArray: bytes)
    }

    func send(bytes: [UInt8]) {
        terminalView.send(bytes)
    }

    func send(text: String) {
        terminalView.send(txt: text)
    }

    var controlPending: Bool {
        get { terminalView.controlModifier }
        set { terminalView.controlModifier = newValue }
    }

    func showKeyboard() {
        _ = terminalView.becomeFirstResponder()
    }

    func hideKeyboard() {
        _ = terminalView.resignFirstResponder()
    }

    /// `ESC [ ? 1 h`（オン）/ `ESC [ ? 1 l`（オフ）を探す。チャンク境界をまたぐ分は直前の末尾を持ち越す
    private func trackCursorKeyMode(_ bytes: ArraySlice<UInt8>) {
        let on: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x68]
        let off: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x6c]
        let buffer = feedTail + Array(bytes)
        var i = 0
        while i + on.count <= buffer.count {
            if buffer[i] == 0x1b {
                let slice = Array(buffer[i ..< i + on.count])
                if slice == on { usesApplicationCursorKeys = true; i += on.count; continue }
                if slice == off { usesApplicationCursorKeys = false; i += off.count; continue }
            }
            i += 1
        }
        feedTail = Array(buffer.suffix(on.count - 1))
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
