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
/// アプリ側はこの protocol だけを見る。バイト列を流し込む（`feed`）、入力を受ける（`onInput`）、
/// サイズ変更を受ける（`onResize`）の 3 つが責務。
@MainActor
protocol TerminalSurface: AnyObject {
    /// SwiftUI に載せる実体の UIView
    var view: UIView { get }
    /// 直近にレイアウトで確定した桁数・行数。初回レイアウト前は nil
    var currentSize: TerminalSize? { get }
    /// キー入力などホストへ送るべきバイト列
    var onInput: ((Data) -> Void)? { get set }
    /// 桁数・行数が変わったとき（PTY の WindowChange を送る契機）
    var onResize: ((TerminalSize) -> Void)? { get set }
    /// ホストからの出力を描画に流す
    func feed(_ bytes: ArraySlice<UInt8>)
    /// キーボードを出す（first responder にする）
    func focus()
}
