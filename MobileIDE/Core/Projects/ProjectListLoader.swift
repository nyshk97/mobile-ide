import Citadel
import Foundation
import NIOCore

/// tmux 側のセッション 1 件
struct TmuxSession: Hashable {
    var name: String
    var attached: Int
    var activity: Date?
}

/// PolePole の projects.json と tmux のセッション一覧を、SSH の exec 1 往復で取る。
enum ProjectListLoader {
    /// exec チャネルは .zshrc を読まないので PATH を前置きする。tmux サーバーが無いときの exit 1 は `|| true` で吸収。
    /// 列はスペース区切りで**名前を最後**に置く（名前にスペースが入りうる。タブ区切りは Citadel の exec 経路で `_` に化けた）
    static let command = "PATH=/opt/homebrew/bin:$PATH; cat \"$HOME/Library/Application Support/polepole/projects.json\"; printf '\\n---SESSIONS---\\n'; tmux list-sessions -F '#{session_attached} #{session_activity} #{session_name}' 2>/dev/null || true"

    private static let separator = "---SESSIONS---"

    struct Fetched {
        var file: ProjectsFile
        var sessions: [TmuxSession]
    }

    @MainActor
    static func fetch(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async throws -> Fetched {
        let client = try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        let output: ByteBuffer
        do {
            output = try await client.executeCommand(command)
        } catch {
            try? await client.close()
            throw ConnectFailure.other("一覧の取得に失敗しました: \(error)")
        }
        try? await client.close()
        let text = String(buffer: output)
        return try parse(text)
    }

    static func parse(_ text: String) throws -> Fetched {
        guard let range = text.range(of: separator) else {
            throw ConnectFailure.other("一覧の応答が壊れています（区切りが無い）")
        }
        let jsonPart = text[..<range.lowerBound]
        let sessionsPart = text[range.upperBound...]
        let json = jsonPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty else {
            throw ConnectFailure.other("projects.json が見つかりません（PolePole が未インストール?）")
        }
        let file: ProjectsFile
        do {
            file = try Project.decodeFile(Data(json.utf8))
        } catch {
            throw ConnectFailure.other("projects.json を読めませんでした: \(error)")
        }
        let sessions: [TmuxSession] = sessionsPart.split(whereSeparator: \.isNewline).compactMap { line in
            // "<attached> <activity> <name...>"。名前は最後なのでスペースを含んでもよい
            let cols = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard cols.count == 3 else { return nil }
            return TmuxSession(
                name: String(cols[2]),
                attached: Int(cols[0]) ?? 0,
                activity: Double(cols[1]).map { Date(timeIntervalSince1970: $0) }
            )
        }
        return Fetched(file: file, sessions: sessions)
    }
}
