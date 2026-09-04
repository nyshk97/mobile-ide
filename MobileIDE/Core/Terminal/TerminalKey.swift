import Foundation

/// キーボードバーが送るキー。バイト列はここで一元管理する。
enum TerminalKey: String, CaseIterable, Identifiable {
    case esc, tab, shiftTab, enter, ctrlC
    case up, down, left, right
    case tilde, slash, dash, pipe

    var id: String { rawValue }

    /// - Parameter applicationCursor: DECCKM がオンなら矢印は `ESC O A` 系、オフなら `ESC [ A` 系
    func bytes(applicationCursor: Bool) -> [UInt8] {
        let esc: UInt8 = 0x1b
        switch self {
        case .esc: return [esc]
        case .tab: return [0x09]
        case .shiftTab: return [esc, 0x5b, 0x5a]          // ESC [ Z
        case .enter: return [0x0d]
        case .ctrlC: return [0x03]
        case .up, .down, .left, .right:
            let final: UInt8
            switch self {
            case .up: final = 0x41
            case .down: final = 0x42
            case .right: final = 0x43
            default: final = 0x44
            }
            return [esc, applicationCursor ? 0x4f : 0x5b, final]  // ESC O x / ESC [ x
        case .tilde: return Array("~".utf8)
        case .slash: return Array("/".utf8)
        case .dash: return Array("-".utf8)
        case .pipe: return Array("|".utf8)
        }
    }

    var isArrow: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }

    /// バーの表示。文字か SF Symbol
    var label: String {
        switch self {
        case .esc: return "esc"
        case .tab: return "tab"
        case .shiftTab: return "⇧tab"
        case .enter: return "⏎"
        case .ctrlC: return "^C"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .tilde: return "~"
        case .slash: return "/"
        case .dash: return "-"
        case .pipe: return "|"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .esc: return "Escape"
        case .tab: return "Tab"
        case .shiftTab: return "Shift Tab"
        case .enter: return "Enter"
        case .ctrlC: return "Control C"
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .tilde, .slash, .dash, .pipe: return label
        }
    }
}
