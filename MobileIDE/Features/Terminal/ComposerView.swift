import Observation
import SwiftUI
import UIKit

/// チャット入力欄の操作口。`TerminalScreen` が持ち、`ComposerTextView` が作る `UITextView` に橋渡しする。
///
/// SwiftUI の `TextEditor` ではカーソル位置への挿入（iOS 18 から）・IME の未確定文字の確定・placeholder ができないので、
/// `UITextView` を `UIViewRepresentable` で包み、外から要る操作だけここに出す
@Observable
@MainActor
final class ComposerController {
    /// 入力欄がキーボードを持っているか（`textViewDidBeginEditing` / `DidEndEditing` で更新）
    private(set) var isFocused = false

    @ObservationIgnored fileprivate weak var textView: UITextView?
    /// view がまだ無いときに focus() が呼ばれたら、作られた直後に出す
    @ObservationIgnored fileprivate var wantsFocus = false
    /// 挿入で本文が変わったことを SwiftUI 側の binding に返す
    @ObservationIgnored fileprivate var onTextChanged: ((String) -> Void)?

    func focus() {
        // view が無い / 画面から外れている（モード切替直後の解放前）なら、次に作られた view が出す
        if let textView, textView.window != nil {
            _ = textView.becomeFirstResponder()
        } else {
            wantsFocus = true
        }
    }

    func blur() {
        wantsFocus = false
        _ = textView?.resignFirstResponder()
    }

    /// 変換中の未確定文字を確定する（送信の直前に呼ぶ。未確定のひらがなを本文に落とす）
    func commitMarkedText() {
        guard let textView, textView.markedTextRange != nil else { return }
        textView.unmarkText()
        onTextChanged?(textView.text ?? "")
    }

    /// カーソル位置（選択があればその範囲を置き換え）に挿入する。view がまだ無ければ末尾に足す
    func insert(_ text: String, into draft: inout String) {
        guard let textView else {
            draft += text
            return
        }
        commitMarkedText()
        let range = textView.selectedRange
        let current = textView.text ?? ""
        guard let swiftRange = Range(range, in: current) else {
            textView.text = current + text
            draft = textView.text
            return
        }
        textView.text = current.replacingCharacters(in: swiftRange, with: text)
        textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        draft = textView.text
        textView.delegate?.textViewDidChange?(textView)
    }

    fileprivate func setFocused(_ focused: Bool) {
        if isFocused != focused { isFocused = focused }
    }
}

/// 入力欄 + 送信ボタン。端末の下（キーボードバーの下）に置く。1 行の高さから最大 6 行まで伸び、それ以上は中でスクロールする
struct ComposerView: View {
    @Binding var text: String
    var controller: ComposerController
    var onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerTextView(text: $text, controller: controller)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("メッセージ")
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .frame(height: ComposerTextView.minHeight)
            .accessibilityLabel("送信")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// `UITextView` の薄い包み。高さは `sizeThatFits` で本文に合わせ、1〜6 行に収める
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var controller: ComposerController

    static let font = UIFont.preferredFont(forTextStyle: .body)
    static let verticalInset: CGFloat = 8
    static var minHeight: CGFloat { ceil(font.lineHeight + verticalInset * 2) }
    static var maxHeight: CGFloat { ceil(font.lineHeight * 6 + verticalInset * 2) }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let view = PlaceholderTextView()
        view.font = Self.font
        view.textContainerInset = UIEdgeInsets(top: Self.verticalInset, left: 6, bottom: Self.verticalInset, right: 6)
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.placeholder = "メッセージ"
        view.keyboardType = .default
        view.returnKeyType = .default  // return は改行。送信はボタン
        view.autocorrectionType = .default
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.text = text
        controller.textView = view
        controller.onTextChanged = { [weak coordinator = context.coordinator] newText in
            coordinator?.parent.text = newText
        }
        if controller.wantsFocus {
            controller.wantsFocus = false
            DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        context.coordinator.parent = self
        // 変換中（未確定文字がある）は書き戻さない。書き戻すと未確定文字が消える / カーソルが先頭に飛ぶ
        guard uiView.markedTextRange == nil, uiView.text != text else { return }
        uiView.text = text
        uiView.updatePlaceholder()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return CGSize(width: proposal.width ?? 0, height: Self.minHeight) }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(max(ceil(fitted), Self.minHeight), Self.maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? PlaceholderTextView)?.updatePlaceholder()
            parent.text = textView.text ?? ""
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.controller.setFocused(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.controller.setFocused(false)
        }
    }
}

/// placeholder 付き `UITextView`（UIKit には無い）
final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholder()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var text: String! {
        didSet { updatePlaceholder() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.font = font
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top,
                                        width: bounds.width - x - textContainerInset.right,
                                        height: font?.lineHeight ?? 20)
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
    }
}
