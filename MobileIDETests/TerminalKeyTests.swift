import XCTest
@testable import MobileIDE

final class TerminalKeyTests: XCTestCase {
    func testArrowsSwitchWithApplicationCursorMode() {
        XCTAssertEqual(TerminalKey.up.bytes(applicationCursor: false), [0x1b, 0x5b, 0x41])    // ESC [ A
        XCTAssertEqual(TerminalKey.up.bytes(applicationCursor: true), [0x1b, 0x4f, 0x41])     // ESC O A
        XCTAssertEqual(TerminalKey.down.bytes(applicationCursor: false), [0x1b, 0x5b, 0x42])
        XCTAssertEqual(TerminalKey.right.bytes(applicationCursor: false), [0x1b, 0x5b, 0x43])
        XCTAssertEqual(TerminalKey.left.bytes(applicationCursor: true), [0x1b, 0x4f, 0x44])
    }

    func testControlAndSpecialKeys() {
        XCTAssertEqual(TerminalKey.esc.bytes(applicationCursor: false), [0x1b])
        XCTAssertEqual(TerminalKey.tab.bytes(applicationCursor: false), [0x09])
        XCTAssertEqual(TerminalKey.shiftTab.bytes(applicationCursor: false), [0x1b, 0x5b, 0x5a])  // ESC [ Z
        XCTAssertEqual(TerminalKey.enter.bytes(applicationCursor: false), [0x0d])
        XCTAssertEqual(TerminalKey.ctrlC.bytes(applicationCursor: false), [0x03])
    }

    func testSymbolsAreUTF8() {
        XCTAssertEqual(TerminalKey.tilde.bytes(applicationCursor: false), Array("~".utf8))
        XCTAssertEqual(TerminalKey.pipe.bytes(applicationCursor: false), Array("|".utf8))
    }

    func testBarActionNames() {
        XCTAssertEqual(KeyboardBar.Action(name: "ctrl"), .toggleControl)
        XCTAssertEqual(KeyboardBar.Action(name: "keyboard"), .toggleKeyboard)
        XCTAssertEqual(KeyboardBar.Action(name: "shiftTab"), .key(.shiftTab))
        XCTAssertNil(KeyboardBar.Action(name: "nope"))
    }
}
