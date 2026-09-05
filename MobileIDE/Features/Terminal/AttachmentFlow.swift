import Foundation
import Observation

/// 画像添付の一連の流れ（変換 → アップロード → 端末に流し込み）と、その表示状態。
///
/// 写真ピッカーからも DEBUG の自走（`MOBILE_IDE_UPLOAD_FILE`）からも同じ `send` を通る。
/// 目印行（`UPLOAD …`）はここで出す（`ImageUploader` は転送しか知らない）。
@Observable
@MainActor
final class AttachmentFlow {
    struct Progress: Equatable {
        /// 何枚目を送っているか（1 始まり）と枚数
        var index: Int
        var total: Int
        var fraction: Double
    }

    struct Alert: Identifiable {
        var id = UUID()
        var title: String
        var message: String
    }

    private(set) var progress: Progress?
    var alert: Alert?

    var isBusy: Bool { progress != nil }

    /// 選んだ画像（元データ）をホストに置いて、パスを端末に流し込む
    func send(
        datas: [Data],
        session: PTYSession,
        settings: ConnectionSettings,
        identity: SSHIdentity,
        knownHosts: KnownHostStore
    ) async {
        guard !isBusy else { return }
        guard session.state == .running else {
            alert = Alert(title: "端末に接続してから選んでください", message: "接続が戻ったらもう一度選んでください。")
            return
        }
        guard !datas.isEmpty else { return }
        print("UPLOAD start n=\(datas.count)")
        fflush(stdout)
        progress = Progress(index: 1, total: datas.count, fraction: 0)
        defer { progress = nil }

        // 変換は重いので MainActor から外す
        let transcoded: [Swift.Result<UploadItem, Error>] = await Task.detached(priority: .userInitiated) {
            datas.map { data in Swift.Result { try ImageTranscoder.transcode(data) } }
        }.value
        let items = transcoded.compactMap { try? $0.get() }
        let transcodeFailures = transcoded.count - items.count
        var reason = transcoded.compactMap { result -> String? in
            if case .failure(let error) = result { return "\(error)" }
            return nil
        }.first

        var paths: [String] = []
        if !items.isEmpty {
            progress = Progress(index: 1, total: items.count, fraction: 0)
            print("UPLOAD progress 1/\(items.count)")
            fflush(stdout)
            var lastIndex = 0
            let result = await ImageUploader.upload(items: items, settings: settings, identity: identity, knownHosts: knownHosts) { [weak self] index, fraction in
                guard let self else { return }
                if index != lastIndex {
                    lastIndex = index
                    print("UPLOAD progress \(index + 1)/\(items.count)")
                    fflush(stdout)
                }
                self.progress = Progress(index: index + 1, total: items.count, fraction: fraction)
            }
            paths = result.paths
            if let failure = result.failure, reason == nil { reason = failure.description }
            if case .hostKeyMismatch = result.failure { reason = result.failure?.description }
        }
        let failed = transcodeFailures + (items.count - paths.count)

        if paths.isEmpty {
            let text = reason ?? "送れませんでした"
            print("UPLOAD failed \(text)".replacingOccurrences(of: "\n", with: " "))
            fflush(stdout)
            alert = Alert(title: "画像を送れませんでした", message: text)
            return
        }

        print("UPLOAD done n=\(paths.count) failed=\(failed)")
        fflush(stdout)
        let text = paths.map { "@\($0) " }.joined()
        if session.state == .running {
            session.send(Data(text.utf8))
            print("UPLOAD typed \(text)")
            fflush(stdout)
            if failed > 0 {
                alert = Alert(title: "\(failed) 枚送れませんでした", message: "\(paths.count) 枚は端末に入力しました。\n\(reason ?? "")")
            }
        } else {
            // 数秒の転送中に再接続に落ちた。send は黙って捨てるので、パスを見せて手で打てるようにする
            alert = Alert(title: "送信しましたが端末に入力できませんでした", message: "接続が戻ったら次を打ってください:\n\(text)")
        }
    }
}
