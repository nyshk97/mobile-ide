import Crypto
import Foundation

extension Curve25519.Signing.PublicKey {
    /// `authorized_keys` に貼れる OpenSSH 形式の 1 行（`ssh-ed25519 <base64> <comment>`）。
    ///
    /// base64 部は RFC 8709 の wire 形式: `string "ssh-ed25519"` + `string <32 バイトの公開鍵>`。
    /// `string` は uint32 (big endian) の長さ + 本体。
    func openSSHAuthorizedKeyLine(comment: String) -> String {
        var blob = Data()
        func appendString(_ bytes: Data) {
            var length = UInt32(bytes.count).bigEndian
            blob.append(Data(bytes: &length, count: 4))
            blob.append(bytes)
        }
        appendString(Data("ssh-ed25519".utf8))
        appendString(rawRepresentation)
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }
}
