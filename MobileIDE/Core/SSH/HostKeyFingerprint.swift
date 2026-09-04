import Crypto
import Foundation
import NIOCore
import NIOSSH

extension NIOSSHPublicKey {
    /// SSH wire 形式（`string type` + 鍵本体）。OpenSSH の公開鍵行の base64 部と同じもの
    var wireBytes: Data {
        var buffer = ByteBuffer()
        _ = write(to: &buffer)
        return Data(buffer.readableBytesView)
    }

    /// wire 形式の先頭にある鍵種別（`ssh-ed25519` など）
    var keyTypeName: String {
        let bytes = wireBytes
        guard bytes.count >= 4 else { return "unknown" }
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard length > 0, bytes.count >= 4 + length else { return "unknown" }
        return String(decoding: bytes[4 ..< 4 + length], as: UTF8.self)
    }

    /// OpenSSH の `ssh-keygen -lf` と同じ表記（`SHA256:` + パディング無し base64）
    var sha256Fingerprint: String {
        let digest = Data(SHA256.hash(data: wireBytes))
        return "SHA256:" + digest.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// known_hosts に書く形（コメント無し）。`NIOSSHPublicKey(openSSHPublicKey:)` で読み戻せる
    var openSSHLine: String {
        "\(keyTypeName) \(wireBytes.base64EncodedString())"
    }
}
