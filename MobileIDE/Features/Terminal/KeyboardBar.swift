import SwiftUI

/// 端末の下に常駐するキーボードバー（#6 → #13 で整理）。
///
/// 並び: [Claude] [Codex] [git ▾] [/ ▾] | tab ^C | ← ↓ ↑ → ⏎ | 入力方式切替 | キーボード切替。狭い画面では横スクロール。
/// 起動系（Claude / Codex / gpull / gpush）は Enter まで送り、スラッシュコマンドは文字列だけ流す（`Shortcut`）。
/// 入力方式（`InputMode`）は右端の 2 つの前に置く。チャット入力欄モードではスラッシュコマンドは入力欄に挿入される（`TerminalScreen`）
struct KeyboardBar: View {
    enum Action: Hashable {
        case key(TerminalKey)
        case shortcut(Shortcut)
        case toggleKeyboard
        case toggleInputMode

        /// 自走検証（MOBILE_IDE_PRESS_KEYS）の名前から
        init?(name: String) {
            if name == "keyboard" {
                self = .toggleKeyboard
            } else if name == "inputMode" {
                self = .toggleInputMode
            } else if let key = TerminalKey(rawValue: name) {
                self = .key(key)
            } else if let shortcut = Shortcut(name: name) {
                self = .shortcut(shortcut)
            } else {
                return nil
            }
        }

        /// 目印行（`KEYS pressed <name>`）に出す名前
        var name: String {
            switch self {
            case .key(let key): return key.rawValue
            case .shortcut(let shortcut): return shortcut.name
            case .toggleKeyboard: return "keyboard"
            case .toggleInputMode: return "inputMode"
            }
        }
    }

    var isKeyboardVisible: Bool
    var inputMode: InputMode
    var perform: (Action) -> Void

    private let keys: [TerminalKey] = [.tab, .ctrlC]
    private let cursorKeys: [TerminalKey] = [.left, .down, .up, .right, .enter]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    launcher(.claude, label: "Claude Code を起動") { ClaudeMark() }
                    launcher(.codex, label: "Codex を起動") { CodexMark() }
                    menu(label: "git", items: [.gpull, .gpush]) { GitMark() }
                    menu(label: "スラッシュコマンド", items: Shortcut.slashCommands.map { .slash($0) }) {
                        Text("/").font(.system(size: 17, design: .monospaced).weight(.medium))
                    }
                    divider
                    ForEach(keys) { keyButton($0) }
                    divider
                    ForEach(cursorKeys) { keyButton($0) }
                }
                .padding(.horizontal, 8)
            }
            Divider().frame(height: 24)
            Button {
                perform(.toggleInputMode)
            } label: {
                Image(systemName: inputMode == .composer ? "apple.terminal" : "text.bubble")
                    .frame(width: 44, height: 34)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel(inputMode == .composer ? "直接入力に切り替える" : "チャット入力に切り替える")
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
    static func keyLabel(_ text: String, pressed: Bool = false) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 36, minHeight: 34)
            .background(Color.secondary.opacity(pressed ? 0.35 : 0.15), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)
    }

    /// マーク付きボタンの枡（起動系・メニューで共通）
    private static func iconWell<Mark: View>(@ViewBuilder mark: () -> Mark) -> some View {
        mark()
            .frame(width: 20, height: 20)
            .frame(width: 40, height: 34)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)
    }

    private var divider: some View {
        Divider().frame(height: 24).padding(.horizontal, 2)
    }

    private func launcher<Mark: View>(_ shortcut: Shortcut, label: String, @ViewBuilder mark: () -> Mark) -> some View {
        Button {
            perform(.shortcut(shortcut))
        } label: {
            Self.iconWell(mark: mark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 上に開くメニュー。項目の並びは `items` の順（`.menuOrder(.fixed)`）
    private func menu<Mark: View>(label: String, items: [Shortcut], @ViewBuilder mark: () -> Mark) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button(item.name) { perform(.shortcut(item)) }
            }
        } label: {
            Self.iconWell(mark: mark)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(label)
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
        KeyboardBar(isKeyboardVisible: true, inputMode: .composer) { _ in }
        KeyboardBar(isKeyboardVisible: false, inputMode: .direct) { _ in }
    }
}
