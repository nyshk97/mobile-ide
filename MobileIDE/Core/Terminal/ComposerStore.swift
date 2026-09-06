import Foundation

/// チャット入力欄の下書きと入力方式を、プロジェクト（tmux セッション名）ごとに UserDefaults に持つ。
///
/// キーは `composer.draft.<session>` / `composer.mode.<session>`。プロジェクトを消しても残るが数十バイトなので掃除はしない。
/// 下書きは**変わるたびに**保存する（`TerminalScreen` の `onChange(of: draft)`）。onDisappear で保存する作りだと、閉じた直後に
/// 同じプロジェクトを開いたとき新しい画面の onAppear が古い画面の onDisappear より先に走って空を読む（自走で実測）。
/// UserDefaults の set はメモリ上の更新なので打鍵ごとでも問題ない
@MainActor
final class ComposerStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func draft(for session: String) -> String {
        defaults.string(forKey: Self.draftKey(session)) ?? ""
    }

    func setDraft(_ text: String, for session: String) {
        if text.isEmpty {
            defaults.removeObject(forKey: Self.draftKey(session))
        } else {
            defaults.set(text, forKey: Self.draftKey(session))
        }
    }

    func mode(for session: String) -> InputMode {
        defaults.string(forKey: Self.modeKey(session)).flatMap(InputMode.init(rawValue:)) ?? .composer
    }

    func setMode(_ mode: InputMode, for session: String) {
        defaults.set(mode.rawValue, forKey: Self.modeKey(session))
    }

    static func draftKey(_ session: String) -> String { "composer.draft.\(session)" }
    static func modeKey(_ session: String) -> String { "composer.mode.\(session)" }
}
