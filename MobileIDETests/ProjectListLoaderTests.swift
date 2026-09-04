import XCTest
@testable import MobileIDE

final class ProjectListLoaderTests: XCTestCase {
    /// ssh exec の実出力（2026-09-04 の Air）をそのまま fixture にしたもの
    static let fixture = """
    {
      "projects" : [
        {
          "colorKey" : "mint",
          "displayName" : "IS",
          "id" : "4C3CA719-DD18-49AE-822C-95A8B5DBC2A9",
          "isPinned" : true,
          "lastOpenedAt" : "2026-07-29T07:08:37Z",
          "paneLayout" : "split",
          "path" : "/Users/d0ne1s/is"
        },
        {
          "displayName" : "mobile-ide",
          "id" : "AAAA",
          "isPinned" : false,
          "lastOpenedAt" : "2026-09-04T01:00:00Z",
          "path" : "/Users/d0ne1s/mobile-ide"
        }
      ],
      "schemaVersion" : 1
    }
    ---SESSIONS---
    0 1788512008 mobile-ide
    1 1788512100 form
    0 1788512200 with space

    """

    func testParseSplitsProjectsAndSessions() throws {
        let fetched = try ProjectListLoader.parse(Self.fixture)
        XCTAssertEqual(fetched.file.schemaVersion, 1)
        XCTAssertEqual(fetched.file.projects.map(\.displayName), ["IS", "mobile-ide"])
        XCTAssertEqual(fetched.file.projects[0].color, .mint)
        XCTAssertEqual(fetched.sessions.map(\.name), ["mobile-ide", "form", "with space"])
        XCTAssertEqual(fetched.sessions.map(\.attached), [0, 1, 0])
        XCTAssertEqual(fetched.sessions[0].activity, Date(timeIntervalSince1970: 1_788_512_008))
    }

    func testParseWithoutTmuxServer() throws {
        let text = Self.fixture.components(separatedBy: "---SESSIONS---")[0] + "---SESSIONS---\n"
        let fetched = try ProjectListLoader.parse(text)
        XCTAssertEqual(fetched.sessions, [])
    }

    func testParseFailsWhenProjectsFileMissing() {
        XCTAssertThrowsError(try ProjectListLoader.parse("\n---SESSIONS---\n"))
    }

    @MainActor
    func testApplyMarksAliveAndAttachedSessions() throws {
        let fetched = try ProjectListLoader.parse(Self.fixture)
        let model = ProjectListModel()
        model.apply(fetched)
        XCTAssertEqual(model.pinned.map(\.sessionName), ["is"])
        XCTAssertEqual(model.pinned.map(\.sessionState), [.none])
        XCTAssertEqual(model.others.map(\.sessionName), ["mobile-ide"])
        XCTAssertEqual(model.others.map(\.sessionState), [.alive])
    }
}

final class ProjectColorTests: XCTestCase {
    /// PolePole のサイドバー（2026-09-04 のスクショ）と同じ色になること
    func testAutomaticColorMatchesPolePole() {
        XCTAssertEqual(ProjectColor.resolve(key: nil, for: "Dropbox"), .mint)
        XCTAssertEqual(ProjectColor.resolve(key: nil, for: "daw"), .blue)
        XCTAssertEqual(ProjectColor.resolve(key: nil, for: "browser"), .yellow)
        XCTAssertEqual(ProjectColor.resolve(key: nil, for: "dmail"), .pink)
        XCTAssertEqual(ProjectColor.resolve(key: nil, for: "mobile-ide"), .green)
    }

    func testExplicitKeyWins() {
        XCTAssertEqual(ProjectColor.resolve(key: "red", for: "Dropbox"), .red)
        XCTAssertEqual(ProjectColor.resolve(key: "unknown", for: "Dropbox"), .mint)
    }
}

final class TmuxSessionNameTests: XCTestCase {
    func testSanitizeReplacesTmuxTargetCharacters() {
        XCTAssertEqual(TmuxSessionName.sanitize("b.c"), "b-c")
        XCTAssertEqual(TmuxSessionName.sanitize("a:b"), "a-b")
        XCTAssertEqual(TmuxSessionName.sanitize("video-player"), "video-player")
        XCTAssertEqual(TmuxSessionName.sanitize("日本語"), "project")
    }

    func testNamesUseDirectoryName() {
        let names = TmuxSessionName.names(forPaths: ["/Users/x/video-player", "/Users/x/a/b.c"])
        XCTAssertEqual(names["/Users/x/video-player"], "video-player")
        XCTAssertEqual(names["/Users/x/a/b.c"], "b-c")
    }

    func testNamesDisambiguateDuplicatesWithParent() {
        let names = TmuxSessionName.names(forPaths: ["/x/app", "/y/app", "/z/other"])
        XCTAssertEqual(names["/x/app"], "app-x")
        XCTAssertEqual(names["/y/app"], "app-y")
        XCTAssertEqual(names["/z/other"], "other")
    }
}
