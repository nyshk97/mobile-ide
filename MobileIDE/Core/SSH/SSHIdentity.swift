import Crypto
import Foundation
import Observation

/// この端末の SSH 鍵（ed25519 1 本）。鍵ストアから読み、無ければ生成して保存する。
@Observable
@MainActor
final class SSHIdentity {
    private(set) var privateKey: Curve25519.Signing.PrivateKey
    /// 鍵ストアへの保存に失敗したときの説明（メモリ上の鍵で動き続けるが、再起動で変わる）
    private(set) var storeError: String?

    private let store: SSHKeyStore
    /// #2 のスパイクが UserDefaults に置いていた seed。初回起動で Keychain に移して消す
    private static let legacyDefaultsKey = "dev.ssh.ed25519.seed"

    var publicKeyLine: String {
        privateKey.publicKey.openSSHAuthorizedKeyLine(comment: "mobile-ide")
    }

    init(store: SSHKeyStore = KeychainSSHKeyStore()) {
        self.store = store
        var storeError: String?
        self.privateKey = Self.loadOrCreate(store: store, storeError: &storeError)
        self.storeError = storeError
    }

    /// 新しい鍵に置き換える。古い鍵で登録した authorized_keys では接続できなくなる
    func regenerate() {
        let key = Curve25519.Signing.PrivateKey()
        do {
            try store.save(key)
            storeError = nil
        } catch {
            storeError = "\(error)"
        }
        privateKey = key
        print("SSH key regenerated")
    }

    private static func loadOrCreate(store: SSHKeyStore, storeError: inout String?) -> Curve25519.Signing.PrivateKey {
        do {
            if let key = try store.load() { return key }
        } catch {
            storeError = "\(error)"
        }
        let defaults = UserDefaults.standard
        if let seed = defaults.data(forKey: legacyDefaultsKey),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) {
            do {
                try store.save(key)
                defaults.removeObject(forKey: legacyDefaultsKey)
                print("SSH key migrated from UserDefaults to keychain")
            } catch {
                storeError = "\(error)"
            }
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        do {
            try store.save(key)
            print("SSH key generated")
        } catch {
            storeError = "\(error)"
        }
        return key
    }
}
