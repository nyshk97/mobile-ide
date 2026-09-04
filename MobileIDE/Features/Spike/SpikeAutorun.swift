import Foundation

/// 自走検証用の環境変数まわり。
///
/// - `MOBILE_IDE_SPIKE_AUTORUN=1` で起動直後にスパイク画面を開いて接続テストを自動実行する
/// - `MOBILE_IDE_SPIKE_HOST` / `MOBILE_IDE_SPIKE_USER` で接続先を上書き（無ければ画面の保存値）
///
/// シミュレータは `SIMCTL_CHILD_` プレフィックス、実機は `devicectl ... --environment-variables` で渡す。
/// 起動時には常に公開鍵行を stdout に出す（`--console` で Mac 側から拾って authorized_keys に登録するため）。
enum SpikeAutorun {
    private static let env = ProcessInfo.processInfo.environment

    static var isRequested: Bool { env["MOBILE_IDE_SPIKE_AUTORUN"] == "1" }
    static var hostOverride: String? { env["MOBILE_IDE_SPIKE_HOST"] }
    static var userOverride: String? { env["MOBILE_IDE_SPIKE_USER"] }

    static func printPublicKey() {
        let key = DevKeyStore.loadOrCreate()
        print("SPIKE pubkey \(key.publicKey.openSSHAuthorizedKeyLine(comment: "mobile-ide-dev"))")
        fflush(stdout)
    }
}
