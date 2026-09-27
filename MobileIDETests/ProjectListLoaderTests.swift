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

    /// 2026-09-27 の mini の走査結果の抜粋 + 未登録 2 件（1 件は同名衝突、1 件は origin なし）
    static let reposFixture = fixture + """
    ---REPOS---
    1790176554 https://github.com/nyshk97/mobile-ide.git /Users/d0ne1s/mobile-ide
    1790169827 git@github.com:d0ne1s-mikkame/form.git /Users/d0ne1s/dm/form
    1790169900 git@github.com:nyshk97/form.git /Users/d0ne1s/form
    1790169000 - /Users/d0ne1s/with space

    """

    func testParseRepos() throws {
        let fetched = try ProjectListLoader.parse(Self.reposFixture)
        XCTAssertEqual(fetched.sessions.map(\.name), ["mobile-ide", "form", "with space"])
        XCTAssertEqual(fetched.repos.map(\.path), ["/Users/d0ne1s/mobile-ide", "/Users/d0ne1s/dm/form", "/Users/d0ne1s/form", "/Users/d0ne1s/with space"])
        XCTAssertEqual(fetched.repos.map(\.slug), ["nyshk97/mobile-ide", "d0ne1s-mikkame/form", "nyshk97/form", nil])
        XCTAssertEqual(fetched.repos[0].modifiedAt, Date(timeIntervalSince1970: 1_790_176_554))
    }

    @MainActor
    func testApplyAddsOnlyUnregisteredReposToOthers() throws {
        let fetched = try ProjectListLoader.parse(Self.reposFixture)
        let model = ProjectListModel()
        model.apply(fetched)
        XCTAssertEqual(model.pinned.map(\.project.displayName), ["IS"])
        // mobile-ide は projects.json にあるので重複しない。その他は lastOpenedAt / mtime の降順で混ざる
        // 未登録 repo の mtime（2026-09-23 頃）は mobile-ide の lastOpenedAt（2026-09-04）より新しい
        XCTAssertEqual(model.others.map(\.project.path), [
            "/Users/d0ne1s/form",
            "/Users/d0ne1s/dm/form",
            "/Users/d0ne1s/with space",
            "/Users/d0ne1s/mobile-ide",
        ])
        // 同名の form は親ディレクトリで区別され、既存の tmux セッション "form" には紐づかない
        let byPath = Dictionary(uniqueKeysWithValues: model.allRows.map { ($0.project.path, $0) })
        XCTAssertEqual(byPath["/Users/d0ne1s/form"]?.sessionName, "form-d0ne1s")
        XCTAssertEqual(byPath["/Users/d0ne1s/dm/form"]?.sessionName, "form-dm")
        XCTAssertEqual(byPath["/Users/d0ne1s/with space"]?.sessionName, "with-space")
        XCTAssertEqual(model.paths.count, 5)
    }

    @MainActor
    func testUnregisteredMatchesStandardizedPath() {
        let registered = [Project(id: "a", path: "/Users/x/app/", displayName: "app")]
        let repos = [LocalRepo(path: "/Users/x/app", slug: nil, modifiedAt: nil)]
        XCTAssertEqual(ProjectListModel.unregistered(repos, registered: registered), [])
    }
}

final class GitHubSlugTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(GitHubSlug.normalize("git@github.com:nyshk97/ide.git"), "nyshk97/ide")
        XCTAssertEqual(GitHubSlug.normalize("https://github.com/nyshk97/Mobile-IDE.git"), "nyshk97/mobile-ide")
        XCTAssertEqual(GitHubSlug.normalize("https://github.com/nyshk97/mobile-ide/"), "nyshk97/mobile-ide")
        XCTAssertEqual(GitHubSlug.normalize("ssh://git@github.com/d0ne1s-mikkame/dm"), "d0ne1s-mikkame/dm")
        XCTAssertNil(GitHubSlug.normalize("-"))
        XCTAssertNil(GitHubSlug.normalize("git@gitlab.com:a/b.git"))
        XCTAssertNil(GitHubSlug.normalize("https://github.com/nyshk97"))
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
