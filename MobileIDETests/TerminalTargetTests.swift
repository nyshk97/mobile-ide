import XCTest
@testable import MobileIDE

final class TerminalTargetTests: XCTestCase {
    func testShellEscapeLeavesSafePathsAlone() {
        XCTAssertEqual(TerminalTarget.shellEscape("/Users/x/video-player"), "/Users/x/video-player")
        XCTAssertEqual(TerminalTarget.shellEscape("/Users/x/a/b.c"), "/Users/x/a/b.c")
    }

    func testShellEscapeQuotesSpacesAndShellCharacters() {
        XCTAssertEqual(TerminalTarget.shellEscape("/Users/x/My Project"), "/Users/x/My\\ Project")
        XCTAssertEqual(TerminalTarget.shellEscape("/x/it's"), "/x/it\\'s")
        XCTAssertEqual(TerminalTarget.shellEscape("/x/$HOME"), "/x/\\$HOME")
        XCTAssertEqual(TerminalTarget.shellEscape("/x/日本語"), "/x/\\日\\本\\語")
        XCTAssertEqual(TerminalTarget.shellEscape(""), "''")
    }

    func testShellEscapeKeepsLeadingTildeForExpansion() {
        XCTAssertEqual(TerminalTarget.shellEscape("~/mobile-ide"), "~/mobile-ide")
        // 先頭以外の ~ は展開されないのでエスケープしてよい
        XCTAssertEqual(TerminalTarget.shellEscape("/x/a~b"), "/x/a\\~b")
    }

    func testLaunchCommandDetachesOtherClientsAndEnablesMouse() {
        let target = TerminalTarget(sessionName: "my-project", workingDirectory: "/Users/x/My Project")
        let mouse = " \\; set-option mouse on"
            + " \\; bind-key -T copy-mode WheelUpPane select-pane '\\;' send-keys -X -N 1 scroll-up"
            + " \\; bind-key -T copy-mode WheelDownPane select-pane '\\;' send-keys -X -N 1 scroll-down"
            + " \\; bind-key -T copy-mode-vi WheelUpPane select-pane '\\;' send-keys -X -N 1 scroll-up"
            + " \\; bind-key -T copy-mode-vi WheelDownPane select-pane '\\;' send-keys -X -N 1 scroll-down"
        XCTAssertEqual(target.launchCommand, "tmux new-session -A -D -s my-project -c /Users/x/My\\ Project" + mouse + "; exit")
        XCTAssertEqual(TerminalTarget.mobileIDE.launchCommand, "tmux new-session -A -D -s mobile-ide -c ~/mobile-ide" + mouse + "; exit")
    }
}

final class ReconnectPolicyTests: XCTestCase {
    func testDelayDoublesAndCaps() {
        XCTAssertEqual((1...7).map { ReconnectPolicy.delaySeconds(attempt: $0) }, [1, 2, 4, 8, 15, 15, 15])
        XCTAssertEqual(ReconnectPolicy.delaySeconds(attempt: 0), 0)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(attempt: 100), ReconnectPolicy.maxDelaySeconds)
    }

    func testProbeTimeoutIsShort() {
        XCTAssertEqual(ReconnectPolicy.probeTimeout, .seconds(3))
    }

    /// sshd の ClientAliveInterval 15 × (CountMax 3 + 1)。scripts/host-setup.sh の値と対で見る
    func testStaleAfterBackgroundMatchesClientAlive() {
        XCTAssertEqual(ReconnectPolicy.staleAfterBackground, .seconds(15 * (3 + 1)))
    }
}
