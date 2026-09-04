import SwiftUI
import UIKit

/// #2 のスパイク画面。使い捨て。#4 で接続設定画面に置き換わったら消す。
struct SSHSpikeView: View {
    @AppStorage("spike.host") private var host = "127.0.0.1"
    @AppStorage("spike.user") private var user = ""
    @State private var results: [SpikeResult] = []
    @State private var running = false
    @State private var copied = false

    private let privateKey = DevKeyStore.loadOrCreate()
    private var publicKeyLine: String {
        privateKey.publicKey.openSSHAuthorizedKeyLine(comment: "mobile-ide-dev")
    }

    var body: some View {
        Form {
            Section("接続先") {
                TextField("ホスト名", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("ユーザー名", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Text(publicKeyLine)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = publicKeyLine
                    copied = true
                } label: {
                    Label(copied ? "コピーしました" : "公開鍵をコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("公開鍵（authorized_keys に貼る）")
            } footer: {
                Text("秘密鍵はこの端末の UserDefaults に置いている（スパイク用の一時保存）。")
            }
            Section {
                Button {
                    Task { await runSpike() }
                } label: {
                    if running {
                        HStack { ProgressView(); Text("実行中…") }
                    } else {
                        Text("接続テスト（exec → PTY → SFTP）")
                    }
                }
                .disabled(running || host.isEmpty || user.isEmpty)
            }
            if !results.isEmpty {
                Section("結果") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(result.ok ? .green : .red)
                                Text(result.step).bold()
                                Spacer()
                                Text(String(format: "%.2fs", result.seconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !result.detail.isEmpty {
                                Text(result.detail)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("SSH スパイク")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 自走検証: 環境変数で接続先を上書きして即実行し、終わったら stdout に目印を出す
            guard SpikeAutorun.isRequested, !running, results.isEmpty else { return }
            if let h = SpikeAutorun.hostOverride { host = h }
            if let u = SpikeAutorun.userOverride { user = u }
            print("SPIKE autorun \(user)@\(host)")
            await runSpike()
            print("SPIKE done")
            fflush(stdout)
        }
    }

    private func runSpike() async {
        running = true
        results = []
        await SSHSpikeRunner.run(host: host, user: user, privateKey: privateKey) { result in
            await MainActor.run { results.append(result) }
        }
        running = false
    }
}

#Preview {
    NavigationStack { SSHSpikeView() }
}
