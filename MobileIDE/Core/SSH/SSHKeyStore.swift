import Crypto
import Foundation
import Security

/// 秘密鍵の保存先。Keychain 実装と、Preview / 検証用のメモリ実装を差し替えられるようにする。
protocol SSHKeyStore {
    func load() throws -> Curve25519.Signing.PrivateKey?
    func save(_ key: Curve25519.Signing.PrivateKey) throws
    func delete() throws
}

struct KeychainError: Error, CustomStringConvertible {
    let status: OSStatus
    var description: String {
        let message = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? ""
        return "Keychain error \(status) \(message)"
    }
}

/// Keychain（GenericPassword）にこの端末限定で保存する。iCloud Keychain に同期されず、バックアップから別端末にも復元されない。
/// AfterFirstUnlock なのは、再接続がロック直後のバックグラウンド復帰でも動くように。
final class KeychainSSHKeyStore: SSHKeyStore {
    private let service = "com.d0ne1s.mobileide.ssh"
    private let account = "ed25519"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> Curve25519.Signing.PrivateKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    func save(_ key: Curve25519.Signing.PrivateKey) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = key.rawRepresentation
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Preview と検証用。プロセスが終わると消える。
final class InMemorySSHKeyStore: SSHKeyStore {
    private var key: Curve25519.Signing.PrivateKey?
    init(key: Curve25519.Signing.PrivateKey? = nil) { self.key = key }
    func load() throws -> Curve25519.Signing.PrivateKey? { key }
    func save(_ key: Curve25519.Signing.PrivateKey) throws { self.key = key }
    func delete() throws { key = nil }
}
