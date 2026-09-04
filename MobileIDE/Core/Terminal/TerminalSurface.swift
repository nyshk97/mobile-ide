import Foundation
import UIKit

/// 端末の桁数と行数。
struct TerminalSize: Equatable, Sendable {
    var cols: Int
    var rows: Int
}

/// 端末エミュレータの差し替え口。
///
/// 今は SwiftTerm（`SwiftTermSurface`）だけだが、将来 libghostty の iOS ターゲットに置き換えられるよう、
/// アプリ側はこの protocol だけを見る。
@MainActor
protocol TerminalSurface: AnyObject {
    /// SwiftUI に載せる実体の UIView
    var view: UIView { get }
    /// 直近にレイアウトで確定した桁数・行数。初回レイアウト前は nil
    var currentSize: TerminalSize? { get }
    /// キー入力などホストへ送るべきバイト列（エミュレータ経由の入力もキーボードバーからの入力もここに集まる）
    var onInput: ((Data) -> Void)? { get set }
    /// 桁数・行数が変わったとき（PTY の WindowChange を送る契機）
    var onResize: ((TerminalSize) -> Void)? { get set }
    /// ホストからの出力を描画に流す
    func feed(_ bytes: ArraySlice<UInt8>)

    // --- キーボードバーからの入力 ---

    /// バイト列をそのまま入力として送る（`onInput` に流れる）
    func send(bytes: [UInt8])
    /// 文字列を入力として送る
    func send(text: String)
    /// Ctrl のワンショット。true にすると次に打った 1 文字に Ctrl が乗り、エミュレータが false に戻す
    var controlPending: Bool { get set }
    /// エミュレータが Ctrl を消費して false に戻したとき（バーの見た目を戻す）
    var onControlReset: (() -> Void)? { get set }
    /// アプリケーションカーソルモード（DECCKM）。矢印の送出列を切り替える
    var usesApplicationCursorKeys: Bool { get }
    /// ソフトウェアキーボードを出す / 閉じる
    func showKeyboard()
    func hideKeyboard()
}
