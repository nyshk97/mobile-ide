import XCTest
@testable import MobileIDE

final class GitHubRepoLoaderTests: XCTestCase {
    static let listFixture = """
    [{"description":"","isPrivate":true,"nameWithOwner":"nyshk97/mobile-ide","pushedAt":"2026-09-27T03:00:00Z"},{"description":"x","isPrivate":false,"nameWithOwner":"nyshk97/New-App","pushedAt":"2026-09-27T05:00:00Z"}]
    ---EXIT 0---
    [{"description":null,"isPrivate":true,"nameWithOwner":"d0ne1s-mikkame/form","pushedAt":"2026-09-20T00:00:00Z"}]
    ---EXIT 0---
    ---REPOS---
    1790176554 https://github.com/nyshk97/mobile-ide.git /Users/d0ne1s/mobile-ide
    1790169827 git@github.com:d0ne1s-mikkame/form.git /Users/d0ne1s/dm/form
    1790169827 git@github.com:d0ne1s-mikkame/form.git /Users/d0ne1s/form-copy/form

    """

    func testParseListMergesOwnersSortedByPush() throws {
        let fetched = try GitHubRepoLoader.parse(Self.listFixture)
        XCTAssertEqual(fetched.repos.map(\.nameWithOwner), ["nyshk97/New-App", "nyshk97/mobile-ide", "d0ne1s-mikkame/form"])
        XCTAssertEqual(fetched.repos[0].name, "New-App")
        XCTAssertEqual(fetched.local.count, 3)
    }

    @MainActor
    func testRowsMarkClonedByOriginAndPreferShallowPath() throws {
        let rows = GitHubRepoModel.rows(try GitHubRepoLoader.parse(Self.listFixture))
        XCTAssertEqual(rows.map(\.localPath), [nil, "/Users/d0ne1s/mobile-ide", "/Users/d0ne1s/dm/form"])
    }

    func testParseListFailsWithGhOutput() {
        let text = "HTTP 401: Requires authentication (https://api.github.com/graphql)\n---EXIT 1---\n[]\n---EXIT 0---\n---REPOS---\n"
        XCTAssertThrowsError(try GitHubRepoLoader.parse(text)) { error in
            XCTAssertTrue("\(error)".contains("HTTP 401"))
            XCTAssertTrue("\(error)".contains("--insecure-storage"))
        }
    }

    func testListCommandCoversOrganizations() {
        XCTAssertTrue(GitHubRepoLoader.listCommand.contains("gh repo list --no-archived"))
        XCTAssertTrue(GitHubRepoLoader.listCommand.contains("gh repo list d0ne1s-mikkame --no-archived"))
        XCTAssertFalse(GitHubRepoLoader.listCommand.contains("lincwell"))
    }

    func testCloneCommandUsesSSHAndHome() {
        let repo = GitHubRepo(nameWithOwner: "nyshk97/new-app", isPrivate: true)
        let command = GitHubRepoLoader.cloneCommand(for: repo)
        XCTAssertTrue(command.hasPrefix("d=\"$HOME\"/new-app;"))
        // `@` と `:` はバックスラッシュでエスケープされる（シェルを通ると元に戻る）
        XCTAssertTrue(command.contains(#"git clone git\@github.com\:nyshk97/new-app.git "$d""#))
    }

    func testParseClone() {
        XCTAssertEqual(
            GitHubRepoLoader.parseClone("Cloning into '/Users/d0ne1s/new-app'...\n---EXIT 0---\n---PATH /Users/d0ne1s/new-app---\n"),
            .cloned(path: "/Users/d0ne1s/new-app")
        )
        XCTAssertEqual(
            GitHubRepoLoader.parseClone("---EXISTS /Users/d0ne1s/new-app---\n"),
            .alreadyExists(path: "/Users/d0ne1s/new-app")
        )
        XCTAssertEqual(
            GitHubRepoLoader.parseClone("Cloning into 'x'...\nERROR: Repository not found.\n---EXIT 128---\n---PATH /Users/d0ne1s/x---\n"),
            .failed("Cloning into 'x'...\nERROR: Repository not found.")
        )
    }

    func testTargetUsesSameSessionNameAsHome() {
        let known = ["/Users/d0ne1s/dm/form", "/Users/d0ne1s/is"]
        let target = GitHubRepoScreen.target(path: "/Users/d0ne1s/form", knownPaths: known)
        XCTAssertEqual(target.sessionName, "form-d0ne1s")
        XCTAssertEqual(target.workingDirectory, "/Users/d0ne1s/form")
        XCTAssertEqual(GitHubRepoScreen.target(path: "/Users/d0ne1s/is", knownPaths: known).sessionName, "is")
    }
}
