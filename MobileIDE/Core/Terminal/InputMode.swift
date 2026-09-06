import Foundation

/// 端末画面の入力方式。プロジェクト（tmux セッション名）ごとに `ComposerStore` が記憶する。
enum InputMode: String, CaseIterable {
    /// チャット入力欄に書いて送信ボタンで送る（既定）。端末はタップしてもキーボードを出さない
    case composer
    /// 端末をタップしてキーボードから 1 キーずつ送る（tab 補完・vim / less・Enter なしの入力用）
    case direct

    var toggled: InputMode { self == .composer ? .direct : .composer }
}
