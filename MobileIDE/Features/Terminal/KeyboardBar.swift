import SwiftUI

/// 端末の下に常駐するキーボードバー。
///
/// 並び: esc ctrl tab ⇧tab ^C | ~ / - | | ← ↓ ↑ → ⏎ | キーボード切替。狭い画面では横スクロール。
struct KeyboardBar: View {
    enum Action: Hashable {
        case key(TerminalKey)
        case toggleControl
        case toggleKeyboard

        /// 自走検証（MOBILE_IDE_PRESS_KEYS）の名前から
        init?(name: String) {
            switch name {
            case "ctrl": self = .toggleControl
            case "keyboard": self = .toggleKeyboard
            default:
                guard let key = TerminalKey(rawValue: name) else { return nil }
                self = .key(key)
            }
        }
    }

    var isControlArmed: Bool
    var isKeyboardVisible: Bool
    var perform: (Action) -> Void

    private let groups: [[TerminalKey]] = [
        [.esc, .tab, .shiftTab, .ctrlC],
        [.tilde, .slash, .dash, .pipe],
        [.left, .down, .up, .right, .enter],
    ]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    keyButton(.esc)
                    controlButton
                    ForEach(groups[0].dropFirst(), id: \.self) { keyButton($0) }
                    divider
                    ForEach(groups[1]) { keyButton($0) }
                    divider
                    ForEach(groups[2]) { keyButton($0) }
                }
                .padding(.horizontal, 8)
            }
            Divider().frame(height: 24)
            Button {
                perform(.toggleKeyboard)
            } label: {
                Image(systemName: isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    .frame(width: 44, height: 34)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .accessibilityLabel(isKeyboardVisible ? "キーボードを閉じる" : "キーボードを出す")
        }
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// キーの見た目を 1 か所に。`.bordered` は左右の余白が大きく 1 画面に 4 つしか並ばないので自前
    static func keyLabel(_ text: String, emphasized: Bool = false, pressed: Bool = false) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 36, minHeight: 34)
            .background(
                emphasized ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(pressed ? 0.35 : 0.15),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(emphasized ? Color.accentColor : Color.primary)
    }

    private var divider: some View {
        Divider().frame(height: 24).padding(.horizontal, 2)
    }

    private var controlButton: some View {
        Button {
            perform(.toggleControl)
        } label: {
            Self.keyLabel("ctrl", emphasized: isControlArmed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Control")
        .accessibilityValue(isControlArmed ? "次のキーに乗せる" : "オフ")
    }

    @ViewBuilder
    private func keyButton(_ key: TerminalKey) -> some View {
        if key.isArrow {
            RepeatKeyButton(label: key.label, accessibilityLabel: key.accessibilityLabel) {
                perform(.key(key))
            }
        } else {
            Button {
                perform(.key(key))
            } label: {
                Self.keyLabel(key.label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(key.accessibilityLabel)
        }
    }
}

/// 押した瞬間に 1 回、0.5 秒押し続けると 0.1 秒間隔で繰り返す（矢印用）。
private struct RepeatKeyButton: View {
    let label: String
    let accessibilityLabel: String
    let fire: () -> Void

    @State private var pressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        KeyboardBar.keyLabel(label, pressed: pressing)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 30, perform: {}) { isPressing in
                if isPressing {
                    pressing = true
                    fire()
                    repeatTask?.cancel()
                    repeatTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        while !Task.isCancelled {
                            fire()
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                } else {
                    pressing = false
                    repeatTask?.cancel()
                    repeatTask = nil
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack {
        Spacer()
        KeyboardBar(isControlArmed: false, isKeyboardVisible: true) { _ in }
        KeyboardBar(isControlArmed: true, isKeyboardVisible: false) { _ in }
    }
}
