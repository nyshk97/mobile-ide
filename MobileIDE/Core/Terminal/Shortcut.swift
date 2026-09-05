import Foundation

/// キーボードバーのショートカット（#13）。端末に流す文字列をここで一元管理する。
///
/// - `claude` / `codex` / `gpull` / `gpush`: コマンドを Enter（`\r`）まで送って即実行する
/// - `slash`: Claude Code のスラッシュコマンド。文字列だけ流して Enter は送らない（引数を続けられる）。
///   `/` 単独は補完リストを出す用途なのでそのまま、それ以外は末尾に空白を付けて補完リストを閉じる
///   （`/dig` で止めると `/dig` と `/dig-lite` が候補に残り、Enter が補完の選択に食われる）
enum Shortcut: Hashable {
    case claude
    case codex
    case gpull
    case gpush
    case slash(String)

    /// スラッシュメニューの並び（issue #13 の順）
    static let slashCommands: [String] = [
        "/", "/dig", "/dig-lite", "/plot", "/polish-plan", "/polish-plan-codex",
        "/act", "/polish-impl", "/polish-impl-codex", "/retro", "/resume",
    ]

    /// 端末に流す文字列
    var text: String {
        switch self {
        case .claude: return "claude --dangerously-skip-permissions\r"
        case .codex: return "codex -a never -s danger-full-access\r"
        case .gpull: return "gpull\r"
        case .gpush: return "gpush\r"
        case .slash(let command): return command == "/" ? command : command + " "
        }
    }

    /// 表示名 = 自走検証（MOBILE_IDE_PRESS_KEYS）の名前
    var name: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gpull: return "gpull"
        case .gpush: return "gpush"
        case .slash(let command): return command
        }
    }

    /// 名前から。`/` で始まればスラッシュコマンド（一覧に無いものも受ける）
    init?(name: String) {
        switch name {
        case "claude": self = .claude
        case "codex": self = .codex
        case "gpull": self = .gpull
        case "gpush": self = .gpush
        default:
            guard name.hasPrefix("/") else { return nil }
            self = .slash(name)
        }
    }
}
