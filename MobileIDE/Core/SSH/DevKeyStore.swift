import Crypto
import Foundation

/// スパイク用の一時的な鍵置き場。ed25519 の秘密鍵（seed 32 バイト）を UserDefaults に置く。
///
/// **本番の保存先ではない。** #4（接続設定と鍵管理）で Keychain に移し、このファイルは消す。
enum DevKeyStore {
    private static let seedKey = "dev.ssh.ed25519.seed"

    /// 保存済みの鍵があれば復元し、無ければ生成して保存する。
    static func loadOrCreate() -> Curve25519.Signing.PrivateKey {
        let defaults = UserDefaults.standard
        if let seed = defaults.data(forKey: seedKey),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        defaults.set(key.rawRepresentation, forKey: seedKey)
        return key
    }
}
