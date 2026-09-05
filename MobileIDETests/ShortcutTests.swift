import XCTest
@testable import MobileIDE

final class ShortcutTests: XCTestCase {
    func testLaunchersRunImmediately() {
        XCTAssertEqual(Shortcut.claude.text, "claude --dangerously-skip-permissions\r")
        XCTAssertEqual(Shortcut.codex.text, "codex -a never -s danger-full-access\r")
        XCTAssertEqual(Shortcut.gpull.text, "gpull\r")
        XCTAssertEqual(Shortcut.gpush.text, "gpush\r")
    }

    func testSlashCommandsDoNotSendEnter() {
        XCTAssertEqual(Shortcut.slash("/").text, "/")           // 補完リストを出す用途なので空白も付けない
        XCTAssertEqual(Shortcut.slash("/dig").text, "/dig ")     // 空白で補完リストを閉じる。Enter は送らない
        XCTAssertEqual(Shortcut.slash("/polish-impl-codex").text, "/polish-impl-codex ")
        for command in Shortcut.slashCommands {
            XCTAssertFalse(Shortcut.slash(command).text.contains("\r"), command)
        }
    }

    func testSlashMenuOrderMatchesIssue() {
        XCTAssertEqual(Shortcut.slashCommands, [
            "/", "/dig", "/dig-lite", "/plot", "/polish-plan", "/polish-plan-codex",
            "/act", "/polish-impl", "/polish-impl-codex", "/retro", "/resume",
        ])
    }

    func testNamesRoundTrip() {
        XCTAssertEqual(Shortcut(name: "claude"), .claude)
        XCTAssertEqual(Shortcut(name: "gpush"), .gpush)
        XCTAssertEqual(Shortcut(name: "/dig"), .slash("/dig"))
        XCTAssertNil(Shortcut(name: "dig"))
        for shortcut in [Shortcut.claude, .codex, .gpull, .gpush, .slash("/retro")] {
            XCTAssertEqual(Shortcut(name: shortcut.name), shortcut)
        }
    }

    func testBarActionNames() {
        XCTAssertEqual(KeyboardBar.Action(name: "claude"), .shortcut(.claude))
        XCTAssertEqual(KeyboardBar.Action(name: "/dig"), .shortcut(.slash("/dig")))
        XCTAssertEqual(KeyboardBar.Action(name: "enter"), .key(.enter))
        XCTAssertEqual(KeyboardBar.Action(name: "keyboard"), .toggleKeyboard)
        XCTAssertNil(KeyboardBar.Action(name: "ctrl"))  // ctrl ボタンは #13 で落とした
    }
}
