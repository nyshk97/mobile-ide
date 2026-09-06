import SwiftTerm
import UIKit

/// マウス追跡中（Claude Code など）の一本指操作をアプリに届く形に変える `TerminalView`。
///
/// SwiftTerm 1.20.0 の iOS はアプリがマウス追跡を有効にすると、
/// - 一本指ドラッグを「ボタン 1 を押したままの移動」として送るので、なぞった範囲が選択になってスクロールできない
/// - フォーカスが無い（キーボードが閉じている）ときのタップは `becomeFirstResponder` するだけで、クリックをアプリに送らない
///
/// upstream の PR #657（v1.21 以降に入る見込み）と同じく、一本指の縦ドラッグは 1 セル行ごとにホイール（ボタン 4 / 5）を送り、
/// 二本指は UIScrollView の従来のスクロールに残し、フォーカス無しのタップはキーボードを出さずにクリックとして転送する。
/// マウス追跡が無いときは何も変えない。#657 を含むリリースに上げたらこのクラスは消す（#14）
final class WheelScrollingTerminalView: TerminalView {
    /// 1 回の `.changed` で送るホイール報告の上限。指を大きく飛ばしたときにアプリを溢れさせない
    static let maxReportsPerEvent = 4

    private var wheelPan: UIPanGestureRecognizer?
    private var unfocusedClick: UnfocusedClickGestureRecognizer?
    /// セル行に満たない移動量の持ち越し
    private var pendingDistance: CGFloat = 0

    /// SwiftTerm の `computeFontDimensions` と同じ式（lineSpacing は既定の 1.0 前提）。`cellDimension` は internal で読めない
    var cellHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    var cellWidth: CGFloat {
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        let scale = max(traitCollection.displayScale, 1)
        return max(1, (width * scale).rounded() / scale)
    }

    /// アプリがマウス追跡を有効にしている（= 一本指がホイール、フォーカス無しのタップがクリックになる）
    var mouseTrackingActive: Bool { wheelPan != nil }

    /// フォーカスが無いときのタップをクリックとして転送するか（SwiftTerm の `singleTap` はこの条件で `becomeFirstResponder` しかしない）
    var shouldForwardUnfocusedTap: Bool { mouseTrackingActive && !isFirstResponder }

    var hasUnfocusedClickRecognizer: Bool { unfocusedClick != nil }

    // tmux は再描画のたびにモードを送り直すので、同じ状態でも何度も呼ばれる（install / remove は冪等）。
    // super は「ドラッグ選択」の pan を付けるので呼ばない
    override func mouseModeChanged(source: Terminal) {
        let tracking = source.mouseMode != .off
        #if DEBUG
        if tracking != mouseTrackingActive {
            print("TERMINAL mouse \(tracking ? "on" : "off")")
            fflush(stdout)
        }
        #endif
        installUnfocusedClickOnce()
        if tracking {
            installWheelPan()
        } else {
            removeWheelPan()
        }
    }

    // MARK: 一本指ドラッグ → ホイール

    private func installWheelPan() {
        guard wheelPan == nil else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleWheelPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        wheelPan = pan
        panGestureRecognizer.minimumNumberOfTouches = 2
    }

    private func removeWheelPan() {
        guard let pan = wheelPan else { return }
        removeGestureRecognizer(pan)
        wheelPan = nil
        pendingDistance = 0
        panGestureRecognizer.minimumNumberOfTouches = 1
    }

    @objc private func handleWheelPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 認識までのスロップ（10pt 程度）を最初の .changed に乗せない
            gesture.setTranslation(.zero, in: self)
            pendingDistance = 0
        case .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            _ = reportWheel(distance: translation.y, at: gesture.location(in: self))
        default:
            pendingDistance = 0
        }
    }

    /// 指の縦移動量をセル行に丸めてホイール報告にする。戻り値は送った行数（符号付き。正 = 上スクロール = ボタン 4）。
    /// 指を下に動かす（distance > 0）と内容が下に動いて古い行が見える = ホイール上、が macOS の `scrollWheel` と同じ向き。
    /// `point` は self の座標（UIScrollView なので contentOffset 込み）
    @discardableResult
    func reportWheel(distance: CGFloat, at point: CGPoint) -> Int {
        let terminal = getTerminal()
        guard allowMouseReporting, terminal.mouseMode != .off, cellHeight > 0 else { return 0 }
        pendingDistance += distance
        let wanted = Int(pendingDistance / cellHeight)  // 0 方向に丸めるので端数は持ち越す
        guard wanted != 0 else { return 0 }
        let lines = wanted.signum() * min(abs(wanted), Self.maxReportsPerEvent)
        // 上限で送らなかった分も消費する（速いフリックの残りを次のイベントに持ち越して溢れさせない。upstream のトークンバケットも捨てる）
        pendingDistance -= CGFloat(wanted) * cellHeight

        let flags = terminal.encodeButton(button: lines > 0 ? 4 : 5, release: false, shift: false, meta: false, control: false)
        let cell = screenCell(at: point, terminal: terminal)
        for _ in 0..<abs(lines) {
            terminal.sendEvent(buttonFlags: flags, x: cell.col, y: cell.row)
        }
        return lines
    }

    // MARK: フォーカス無しのタップ → クリック

    /// 一度だけ付ける。SwiftTerm の singleTap（1 回タップ）にこちらの失敗を待たせる（`require(toFail:)`）ので、
    /// 転送する条件ではこちらだけが走り、転送しない条件では `touchesBegan` で即失敗して singleTap が従来通り動く。
    /// 付けたり外したりすると failure requirement が外れた recognizer を指したまま残るので、常設にして条件で失敗させる
    private func installUnfocusedClickOnce() {
        guard unfocusedClick == nil else { return }
        let click = UnfocusedClickGestureRecognizer(target: self, action: #selector(handleUnfocusedClick(_:)))
        click.shouldRecognize = { [weak self] in self?.shouldForwardUnfocusedTap ?? false }
        addGestureRecognizer(click)
        unfocusedClick = click
        for case let tap as UITapGestureRecognizer in gestureRecognizers ?? []
        where tap !== click && tap.numberOfTapsRequired == 1 && tap.numberOfTouchesRequired == 1 {
            tap.require(toFail: click)
        }
    }

    @objc private func handleUnfocusedClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        forwardClick(at: gesture.location(in: self))
    }

    /// 左ボタンの押下と解放をアプリに送る（PR #657 の `forwardTap(at:)` 相当）。追跡していなければ何もしない
    @discardableResult
    func forwardClick(at point: CGPoint) -> Bool {
        let terminal = getTerminal()
        guard allowMouseReporting, terminal.mouseMode != .off else { return false }
        let cell = screenCell(at: point, terminal: terminal)
        terminal.sendEvent(buttonFlags: terminal.encodeButton(button: 0, release: false, shift: false, meta: false, control: false),
                           x: cell.col, y: cell.row)
        if terminal.mouseMode != .x10 {  // X10 互換モードは押下だけ
            terminal.sendEvent(buttonFlags: terminal.encodeButton(button: 0, release: true, shift: false, meta: false, control: false),
                               x: cell.col, y: cell.row)
        }
        return true
    }

    /// self の座標（contentOffset 込み）を画面上のセル位置に。SwiftTerm の `calculateTapHit` → `toScreenCoordinate` 相当
    private func screenCell(at point: CGPoint, terminal: Terminal) -> (col: Int, row: Int) {
        let col = clamp(Int((point.x - contentOffset.x) / cellWidth), 0, terminal.cols - 1)
        let row = clamp(Int((point.y - contentOffset.y) / cellHeight), 0, terminal.rows - 1)
        return (col, row)
    }

    private func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), max(lower, upper))
    }
}

/// フォーカス無し・マウス追跡中のタップだけ認識するタップ。それ以外は `touchesBegan` で即失敗し、
/// `require(toFail:)` で待っている SwiftTerm の singleTap に譲る
final class UnfocusedClickGestureRecognizer: UITapGestureRecognizer {
    var shouldRecognize: () -> Bool = { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard shouldRecognize() else {
            state = .failed
            return
        }
        super.touchesBegan(touches, with: event)
    }
}
