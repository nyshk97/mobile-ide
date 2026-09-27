import Citadel
import Foundation
import NIOCore

/// `gh repo list --json` の 1 件
struct GitHubRepo: Decodable, Hashable, Identifiable {
    var nameWithOwner: String
    var description: String?
    var pushedAt: Date?
    var isPrivate: Bool

    var id: String { nameWithOwner }
    var slug: String { nameWithOwner.lowercased() }
    /// `owner/name` の name。clone 先 `~/<name>` に使う
    var name: String { String(nameWithOwner.split(separator: "/").last ?? Substring(nameWithOwner)) }
}

/// 「GitHub から追加」の一覧と clone。どちらもホストの gh / git を SSH の exec で叩く。
///
/// Citadel の `executeCommand` は終了コードが 0 以外でも stderr に何か出ても throw して出力を捨てるので、
/// コマンドは全部 `2>&1` にし、終了コードは `---EXIT n---` の行で受け取って最後は必ず 0 で終わらせる。
/// ホストの gh は SSH からキーチェーンを読めないので `--insecure-storage`（`~/.config/gh/hosts.yml`）で認証しておく（VERIFY.md のホスト）
enum GitHubRepoLoader {
    /// 個人に加えて並べる org。仕事の org は出さない
    static let organizations = ["d0ne1s-mikkame"]

    private static let fields = "nameWithOwner,description,pushedAt,isPrivate"
    private static let reposSeparator = "---REPOS---"

    static var listCommand: String {
        let owners = [""] + organizations
        let lists = owners.map { owner in
            "gh repo list \(owner.isEmpty ? "" : TerminalTarget.shellEscape(owner) + " ")--no-archived --limit 500 --json \(fields) 2>&1; echo \"---EXIT $?---\""
        }
        return (["PATH=/opt/homebrew/bin:$PATH"] + lists + ["printf '\(reposSeparator)\\n'", LocalRepoScan.command]).joined(separator: "; ")
    }

    struct Fetched {
        var repos: [GitHubRepo]
        var local: [LocalRepo]
    }

    @MainActor
    static func fetch(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async throws -> Fetched {
        try parse(try await run(listCommand, settings: settings, identity: identity, knownHosts: knownHosts))
    }

    static func parse(_ text: String) throws -> Fetched {
        guard let range = text.range(of: reposSeparator) else {
            throw ConnectFailure.other("GitHub の一覧の応答が壊れています（区切りが無い）")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var repos: [GitHubRepo] = []
        for (output, code) in splitExits(String(text[..<range.lowerBound])) {
            guard code == 0 else {
                // gh は SSH からキーチェーンを読めないと 401 / "token ... is invalid" になる
                let hint = output.range(of: "auth", options: .caseInsensitive) != nil || output.contains("token")
                    ? "\n\nホストの gh が SSH から認証できていません。ホストの画面のターミナルで `gh auth token | gh auth login --with-token --insecure-storage` を実行してください"
                    : ""
                throw ConnectFailure.other("gh repo list が失敗しました（exit \(code)）\n\(output)\(hint)")
            }
            do {
                repos += try decoder.decode([GitHubRepo].self, from: Data(output.utf8))
            } catch {
                throw ConnectFailure.other("gh repo list の出力を読めませんでした: \(error)\n\(output.prefix(300))")
            }
        }
        var seen = Set<String>()
        repos = repos.filter { seen.insert($0.slug).inserted }
            .sorted { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }
        return Fetched(repos: repos, local: LocalRepoScan.parse(text[range.upperBound...]))
    }

    enum CloneResult: Equatable {
        case cloned(path: String)
        case alreadyExists(path: String)
        case failed(String)
    }

    /// `~/<name>` に clone する。https は gh の credential helper（= キーチェーン）に当たるので SSH の URL で取る。
    /// プロンプトで止まらないよう BatchMode と GIT_TERMINAL_PROMPT=0
    static func cloneCommand(for repo: GitHubRepo) -> String {
        let dir = "\"$HOME\"/" + TerminalTarget.shellEscape(repo.name)
        let url = TerminalTarget.shellEscape("git@github.com:\(repo.nameWithOwner).git")
        return "d=\(dir); if [ -e \"$d\" ]; then echo \"---EXISTS $d---\"; else GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' git clone \(url) \"$d\" 2>&1; echo \"---EXIT $?---\"; echo \"---PATH $d---\"; fi"
    }

    @MainActor
    static func clone(_ repo: GitHubRepo, settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async throws -> CloneResult {
        parseClone(try await run(cloneCommand(for: repo), settings: settings, identity: identity, knownHosts: knownHosts))
    }

    static func parseClone(_ text: String) -> CloneResult {
        if let path = marker("EXISTS", in: text) { return .alreadyExists(path: path) }
        let results = splitExits(text)
        guard let (output, code) = results.first else { return .failed(text) }
        if code == 0, let path = marker("PATH", in: text) { return .cloned(path: path) }
        return .failed(output.isEmpty ? "git clone が失敗しました（exit \(code)）" : output)
    }

    // MARK: -

    @MainActor
    private static func run(_ command: String, settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async throws -> String {
        let client = try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        defer { Task { try? await client.close() } }
        do {
            return String(buffer: try await client.executeCommand(command))
        } catch {
            throw ConnectFailure.other("コマンドの実行に失敗しました: \(error)")
        }
    }

    /// `<出力>---EXIT n---` の並びを (出力, n) に分ける
    static func splitExits(_ text: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        var rest = Substring(text)
        while let start = rest.range(of: "---EXIT ") {
            guard let end = rest[start.upperBound...].range(of: "---") else { break }
            let output = rest[..<start.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let code = Int(rest[start.upperBound..<end.lowerBound]) ?? -1
            result.append((output, code))
            rest = rest[end.upperBound...]
        }
        return result
    }

    private static func marker(_ name: String, in text: String) -> String? {
        guard let start = text.range(of: "---\(name) "),
              let end = text[start.upperBound...].range(of: "---") else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}
