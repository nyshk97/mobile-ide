import SwiftUI
import UIKit

/// 接続先・この端末の鍵・ホスト鍵・接続テスト。
struct SettingsScreen: View {
    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts

    @State private var testing = false
    @State private var testResult: SSHConnection.TestResult?
    @State private var copied = false
    @State private var confirmRegenerate = false
    @State private var mismatch: (expected: String, actual: String, actualLine: String)?
    @State private var showMismatch = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("接続先") {
                TextField("ホスト名（例: mac-mini.tail1234.ts.net）", text: $settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("ポート", value: $settings.port, format: .number)
                    .keyboardType(.numberPad)
                TextField("ユーザー名", text: $settings.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Text(identity.publicKeyLine)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = identity.publicKeyLine
                    copied = true
                } label: {
                    Label(copied ? "コピーしました" : "公開鍵をコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button("鍵を作り直す", role: .destructive) { confirmRegenerate = true }
                    .confirmationDialog(
                        "鍵を作り直しますか？",
                        isPresented: $confirmRegenerate,
                        titleVisibility: .visible
                    ) {
                        Button("作り直す", role: .destructive) {
                            identity.regenerate()
                            copied = false
                            testResult = nil
                        }
                    } message: {
                        Text("古い鍵での接続はできなくなります。新しい公開鍵を Mac の ~/.ssh/authorized_keys に登録してください。")
                    }
            } header: {
                Text("この端末の鍵")
            } footer: {
                if let error = identity.storeError {
                    Text("Keychain に保存できていません: \(error)").foregroundStyle(.red)
                } else {
                    Text("秘密鍵はこの端末の Keychain にあり、iCloud には同期されません。公開鍵を Mac の ~/.ssh/authorized_keys に 1 行追加してください。")
                }
            }

            Section {
                if let line = knownHosts.line(host: settings.host, port: settings.port),
                   let key = try? NIOSSHPublicKeyBox(line: line) {
                    LabeledContent("指紋") {
                        Text(key.fingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button("このホスト鍵を忘れる", role: .destructive) {
                        knownHosts.remove(host: settings.host, port: settings.port)
                    }
                } else {
                    Text("未登録。初回接続時に受け取った鍵を記録し、以降は照合します。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("ホスト鍵（\(settings.host.isEmpty ? "-" : settings.host):\(settings.port)）")
            } footer: {
                Text("Mac 側では ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub で同じ指紋が出ます。")
            }

            Section("接続テスト") {
                Button {
                    Task { await runTest() }
                } label: {
                    if testing {
                        HStack { ProgressView(); Text("接続中…") }
                    } else {
                        Text("接続してみる")
                    }
                }
                .disabled(testing || !settings.isConfigured)
                if let result = testResult {
                    HStack(alignment: .top) {
                        Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.ok ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(result.ok ? "接続できました" : "接続できませんでした")
                            Text(result.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.2fs", result.seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ホスト鍵が変わりました", isPresented: $showMismatch, presenting: mismatch) { m in
            Button("新しい鍵を信用") {
                knownHosts.set(m.actualLine, host: settings.host, port: settings.port)
                Task { await runTest() }
            }
            Button("接続しない", role: .cancel) {}
        } message: { m in
            Text("記録: \(m.expected)\n今回: \(m.actual)\n\nMac を入れ替えた・再インストールした覚えがなければ接続しないでください。")
        }
        .task {
            guard LaunchOptions.connectionTest, testResult == nil, !testing else { return }
            await runTest()
        }
    }

    private func runTest() async {
        testing = true
        testResult = nil
        let result = await SSHConnection.test(settings: settings, identity: identity, knownHosts: knownHosts)
        testResult = result
        testing = false
        if !result.ok, let m = SSHConnection.lastMismatch(in: result) {
            mismatch = m
            showMismatch = true
        }
    }
}

/// 設定画面で known_hosts の行から指紋を出すための薄い箱
private struct NIOSSHPublicKeyBox {
    let fingerprint: String
    init(line: String) throws {
        fingerprint = try NIOSSHPublicKey(openSSHPublicKey: line).sha256Fingerprint
    }
}

import NIOSSH
