import Foundation

/// 自走検証用の環境変数。シミュレータは `SIMCTL_CHILD_`、実機は `DEVICECTL_CHILD_` のプレフィックスで渡す
/// （`scripts/console-run.py --env KEY=VALUE` が付ける）。
///
/// - `MOBILE_IDE_TERMINAL_AUTORUN=1`: 起動直後に `mobile-ide` の端末画面を開く（一覧を経由しない）
/// - `MOBILE_IDE_OPEN_PROJECT=<sessionName>`: 一覧を読み終えたら該当行の端末を開く
/// - `MOBILE_IDE_TERMINAL_TYPE=<text>`: 端末接続後 1 秒待ってその文字列を送る（`\n` は改行に展開）
/// - `MOBILE_IDE_PRESS_KEYS=tab,enter,claude,gpull,/dig,keyboard`（DEBUG のみ）: 端末接続後、キーボードバーの操作を順に再現する。
///   `TerminalKey` の名前（バーに無い esc 等も可）、ショートカット（`claude` / `codex` / `gpull` / `gpush` / `/` 始まり）、
///   `keyboard`（キーボード切替）、`inputMode`（チャット入力 ⇄ 直接入力の切替）
/// - `MOBILE_IDE_DRAFT=<text>`（DEBUG のみ）: pressKeys の後、チャット入力欄に入れるだけで送信しない（下書き保存の検証用）
/// - `MOBILE_IDE_COMPOSE=<text>`（DEBUG のみ）: pressKeys の後 `MOBILE_IDE_COMPOSE_AFTER` 秒（既定 1）待ってチャット入力欄に入れて送信する
///   （`\n` は改行に展開。`COMPOSE sent bytes=<n>` が出る）。Claude / Codex を pressKeys で起こしてから送るなら待ちを 8 秒程度にする
///   DRAFT / COMPOSE は direct モードでも下書き（保存される）に書いて送るので、composer モードで使うこと
/// - `MOBILE_IDE_INPUT_MODE=composer|direct`（DEBUG のみ）: 端末画面を開くときの入力方式を上書きする（保存はしない。
///   保存 → 通常起動での復元の経路は、これを付けずに開き直して `COMPOSE mode=` で見る）
/// - `MOBILE_IDE_PROBE_AFTER=<秒>`（DEBUG のみ）: 端末接続の N 秒後に生存判定（フォアグラウンド復帰と同じ経路）を呼ぶ。
///   背面に回す経路自体は `xcrun simctl launch booted com.apple.Preferences` → `simctl launch booted <bundle>` で再現できるが、
///   起動オプションのほうが速くて安定するので自走ではこちらを使う
/// - `MOBILE_IDE_RESUME_AFTER=<待ち秒>,<バックグラウンドにいたことにする秒>`（DEBUG のみ）: 端末接続の N 秒後に「M 秒前にバックグラウンドへ
///   入っていた」ことにして復帰（`verifyAlive()`）を呼ぶ。M が閾値を超えていれば probe せず即再接続する経路を見る
/// - `MOBILE_IDE_UPLOAD_FILE=<path>[,<path>…]`（DEBUG のみ）: 端末接続後、ホスト側のそのファイルを画像添付と同じ経路
///   （変換 → SFTP → `@path ` の流し込み）で送る。`MOBILE_IDE_UPLOAD_AFTER=<秒>`（既定 0）で発火を遅らせる
/// - `MOBILE_IDE_CLOSE_AFTER=<秒>`（DEBUG のみ）: 端末接続の N 秒後に端末画面を閉じる（一覧に戻る）。閉じたときに
///   `TERMINAL surface deinit` / `TERMINAL session deinit` / `TERMINAL view released` が出ることでリークしていないことを見る。
///   `MOBILE_IDE_OPEN_TIMES=<回>`（DEBUG のみ、既定 1）で `MOBILE_IDE_OPEN_PROJECT` の自動オープンを閉じるたびに繰り返す
///   （端末 view は UIKit のキーボードが最後の first responder として 1 個だけ握るので、2 回目の close で 1 回目の view が解放されたかを見る）
/// - `MOBILE_IDE_CONNECTION_TEST=1`: 起動直後に設定画面を開いて接続テストを実行する
/// - `MOBILE_IDE_HOST` / `MOBILE_IDE_PORT` / `MOBILE_IDE_USER`: 接続設定を上書き（保存はしない）
/// - `MOBILE_IDE_SAVE_SETTINGS=1`（DEBUG のみ）: 上書き値を UserDefaults にも保存する。手入力と同じ保存経路（setter → didSet）を自走検証・焼き込みに使う
/// - `MOBILE_IDE_KNOWNHOST=forget` / `=<OpenSSH 公開鍵行>`（DEBUG のみ）: 起動時に接続先のホスト鍵の記録を消す / 差し替える。
///   TOFU の不一致経路を外から起こすため（シミュレータの UserDefaults は外から安全に書き換えられない）
enum LaunchOptions {
    private static let env = ProcessInfo.processInfo.environment

    /// 目印行に載せる個体の識別子（ポインタ）。`@State` の初期値は捨てられることがあり、配線された個体と deinit した個体を突き合わせるのに使う
    static func objectID(_ object: AnyObject) -> String {
        "\(Unmanaged.passUnretained(object).toOpaque())"
    }

    static var terminalAutorun: Bool { env["MOBILE_IDE_TERMINAL_AUTORUN"] == "1" }
    static var terminalTextToType: String? {
        env["MOBILE_IDE_TERMINAL_TYPE"]?.replacingOccurrences(of: "\\n", with: "\n")
    }
    static var pressKeys: [String]? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_PRESS_KEYS"], !value.isEmpty else { return nil }
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #else
        return nil
        #endif
    }
    static var draftText: String? {
        #if DEBUG
        return env["MOBILE_IDE_DRAFT"].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "\\n", with: "\n") }
        #else
        return nil
        #endif
    }
    static var composeText: String? {
        #if DEBUG
        return env["MOBILE_IDE_COMPOSE"].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "\\n", with: "\n") }
        #else
        return nil
        #endif
    }
    static var composeAfter: Double {
        #if DEBUG
        return env["MOBILE_IDE_COMPOSE_AFTER"].flatMap(Double.init) ?? 1
        #else
        return 1
        #endif
    }
    static var inputModeOverride: InputMode? {
        #if DEBUG
        return env["MOBILE_IDE_INPUT_MODE"].flatMap(InputMode.init(rawValue:))
        #else
        return nil
        #endif
    }
    static var probeAfter: Double? {
        #if DEBUG
        return env["MOBILE_IDE_PROBE_AFTER"].flatMap(Double.init)
        #else
        return nil
        #endif
    }
    static var resumeAfter: (wait: Double, background: Double)? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_RESUME_AFTER"] else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
        #else
        return nil
        #endif
    }
    static var uploadFiles: [String]? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_UPLOAD_FILE"], !value.isEmpty else { return nil }
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #else
        return nil
        #endif
    }
    static var closeAfter: Double? {
        #if DEBUG
        return env["MOBILE_IDE_CLOSE_AFTER"].flatMap(Double.init)
        #else
        return nil
        #endif
    }
    static var uploadAfter: Double {
        #if DEBUG
        return env["MOBILE_IDE_UPLOAD_AFTER"].flatMap(Double.init) ?? 0
        #else
        return 0
        #endif
    }
    static var openProject: String? { env["MOBILE_IDE_OPEN_PROJECT"].flatMap { $0.isEmpty ? nil : $0 } }
    static var openProjectTimes: Int {
        #if DEBUG
        return env["MOBILE_IDE_OPEN_TIMES"].flatMap(Int.init) ?? 1
        #else
        return 1
        #endif
    }
    static var connectionTest: Bool { env["MOBILE_IDE_CONNECTION_TEST"] == "1" }
    static var hostOverride: String? { env["MOBILE_IDE_HOST"] }
    static var portOverride: Int? { env["MOBILE_IDE_PORT"].flatMap(Int.init) }
    static var userOverride: String? { env["MOBILE_IDE_USER"] }
    static var saveSettings: Bool {
        #if DEBUG
        return env["MOBILE_IDE_SAVE_SETTINGS"] == "1"
        #else
        return false
        #endif
    }

    enum KnownHostOverride {
        case forget
        case replace(String)
    }

    static var knownHostOverride: KnownHostOverride? {
        #if DEBUG
        guard let value = env["MOBILE_IDE_KNOWNHOST"], !value.isEmpty else { return nil }
        return value == "forget" ? .forget : .replace(value)
        #else
        return nil
        #endif
    }
}
