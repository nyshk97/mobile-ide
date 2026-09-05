import Citadel
import Foundation
import NIOCore

/// ホストに置くファイル名。`yyyyMMdd-HHmmss-<バッチ内の連番>.<ext>`（端末のローカル時刻）
enum UploadName {
    static func make(ext: String, now: Date = Date(), index: Int, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: now))-\(index).\(ext)"
    }
}

/// 画像をアップロード専用の SSH 接続で `~/.claude/uploads/` に置く。
///
/// 端末の接続（`PTYSession`）は再接続で入れ替わるので相乗りせず、選んだときだけ張って閉じる。
/// 途中で失敗しても、そこまでに置けたパスは返す（呼び出し側が成功分だけ流し込む）。
enum ImageUploader {
    struct Result {
        var paths: [String]
        /// 最初の失敗。`SSHConnection.connect` の `ConnectFailure`（ホスト鍵不一致を含む）は包まずそのまま
        var failure: ConnectFailure?
    }

    static let directoryUnderHome = ".claude/uploads"
    /// SFTP の 1 回の write に渡す大きさ。Citadel が内部で 32,000 バイトずつ送るので、進捗の粒度を決めるだけ
    static let chunkSize = 256 * 1024

    /// - Parameter progress: `(index, fraction)`。index は 0 始まりの何枚目か、fraction はその枚の進み（0...1）
    @MainActor
    static func upload(
        items: [UploadItem],
        settings: ConnectionSettings,
        identity: SSHIdentity,
        knownHosts: KnownHostStore,
        progress: @escaping @MainActor (Int, Double) -> Void
    ) async -> Result {
        let client: SSHClient
        do {
            client = try await SSHConnection.connect(settings: settings, identity: identity, knownHosts: knownHosts)
        } catch let failure as ConnectFailure {
            return Result(paths: [], failure: failure)
        } catch {
            return Result(paths: [], failure: .other("\(error)"))
        }
        defer { Task { try? await client.close() } }

        var paths: [String] = []
        do {
            // exec は .zshrc を読まないが $HOME は入っている。mkdir -p なので既にあっても通る
            _ = try await client.executeCommand("/bin/mkdir -p \"$HOME/\(directoryUnderHome)\"")
            let sftp = try await client.openSFTP()
            defer { Task { try? await sftp.close() } }
            let home = try await sftp.getRealPath(atPath: ".")
            let directory = "\(home)/\(directoryUnderHome)"
            let now = Date()
            for (index, item) in items.enumerated() {
                let path = "\(directory)/\(UploadName.make(ext: item.ext, now: now, index: index + 1))"
                do {
                    try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                        var offset = 0
                        let total = item.data.count
                        while offset < total {
                            let end = min(offset + chunkSize, total)
                            try await file.write(ByteBuffer(bytes: item.data[offset ..< end]), at: UInt64(offset))
                            offset = end
                            let fraction = Double(offset) / Double(max(total, 1))
                            await progress(index, fraction)
                        }
                    }
                } catch {
                    throw UploadFailure(index: index, error: error)
                }
                paths.append(path)
                print("UPLOAD put \(path) \(item.data.count)")
                fflush(stdout)
            }
            return Result(paths: paths, failure: nil)
        } catch let failure as UploadFailure {
            return Result(paths: paths, failure: .other("\(failure.index + 1) 枚目の転送に失敗しました: \(failure.error)"))
        } catch {
            return Result(paths: paths, failure: .other("アップロードの準備に失敗しました: \(error)"))
        }
    }

    private struct UploadFailure: Error {
        var index: Int
        var error: Error
    }
}
