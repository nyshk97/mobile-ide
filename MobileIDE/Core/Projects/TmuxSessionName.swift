import Foundation

/// プロジェクトの path から tmux のセッション名を作る。
///
/// - 基本はディレクトリ名（`/Users/x/video-player` → `video-player`）
/// - `.` と `:` は tmux のターゲット構文（`-t session:window.pane`）と衝突して指定できなくなるので、
///   `[A-Za-z0-9_-]` 以外は `-` に置き換える
/// - 一覧内でディレクトリ名が重複したら親ディレクトリ名を後ろに付ける（`app-x` / `app-y`）
enum TmuxSessionName {
    static func sanitize(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let mapped = String(raw.map { allowed.contains($0) ? $0 : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "project" : trimmed
    }

    /// path ごとのセッション名。同じ path が複数あれば同じ名前になる
    static func names(forPaths paths: [String]) -> [String: String] {
        func components(_ path: String) -> [String] {
            URL(fileURLWithPath: path).standardizedFileURL.pathComponents.filter { $0 != "/" }
        }
        var base: [String: String] = [:]
        for path in paths {
            base[path] = sanitize(components(path).last ?? path)
        }
        var byName: [String: [String]] = [:]
        for (path, name) in base { byName[name, default: []].append(path) }

        var result: [String: String] = [:]
        for (name, group) in byName {
            let unique = Set(group)
            if unique.count <= 1 {
                for path in group { result[path] = name }
                continue
            }
            for path in unique {
                let parts = components(path)
                let parent = parts.count >= 2 ? sanitize(parts[parts.count - 2]) : "root"
                result[path] = "\(name)-\(parent)"
            }
        }
        return result
    }
}
