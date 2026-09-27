import Foundation

/// ホストの `~/*` と `~/*/*` にある git リポジトリ 1 件。PolePole に未登録のものを一覧に足すのと、
/// 「GitHub から追加」で clone 済みかを判定するのに使う。
struct LocalRepo: Hashable {
    var path: String
    /// `origin` を `owner/name`（小文字）に正規化したもの。origin が無い・GitHub でなければ nil
    var slug: String?
    /// `.git/index`（無ければ `.git`）の mtime。「その他」の並びに使う
    var modifiedAt: Date?
}

enum LocalRepoScan {
    /// 1 行 `<mtime> <origin URL か -> <path>`。path は最後の列（スペースを含みうる）。
    /// zsh の exec ではマッチしないグロブがエラーになるので find で探す。`~/Library` と `~/.*`、node_modules は潜らない
    static let command = #"find "$HOME" -maxdepth 3 \( -path "$HOME/Library" -o -path "$HOME/.*" -o -name node_modules \) -prune -o -name .git -print 2>/dev/null | while IFS= read -r g; do d=${g%/.git}; m=$(stat -f %m "$g/index" 2>/dev/null || stat -f %m "$g"); u=$(git -C "$d" remote get-url origin 2>/dev/null || echo -); printf '%s %s %s\n' "$m" "$u" "$d"; done"#

    static func parse<S: StringProtocol>(_ text: S) -> [LocalRepo] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cols = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard cols.count == 3 else { return nil }
            return LocalRepo(
                path: String(cols[2]),
                slug: GitHubSlug.normalize(String(cols[1])),
                modifiedAt: Double(cols[0]).map { Date(timeIntervalSince1970: $0) }
            )
        }
    }
}

enum GitHubSlug {
    /// `git@github.com:o/r.git` / `ssh://git@github.com/o/r` / `https://github.com/o/r(.git)(/)` → `o/r`（小文字）
    static func normalize(_ url: String) -> String? {
        var rest: Substring
        let url = url.trimmingCharacters(in: .whitespaces)
        if let r = url.range(of: "github.com:") ?? url.range(of: "github.com/") {
            rest = url[r.upperBound...]
        } else {
            return nil
        }
        while rest.hasSuffix("/") { rest = rest.dropLast() }
        if rest.hasSuffix(".git") { rest = rest.dropLast(4) }
        let parts = rest.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return parts.joined(separator: "/").lowercased()
    }
}
