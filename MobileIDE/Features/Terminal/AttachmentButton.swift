import PhotosUI
import SwiftUI

/// ナビゲーションバーの写真ボタン。PhotosPicker（権限不要）で最大 4 枚選び、元データを `onPicked` に渡す。
struct AttachmentButton: View {
    let isBusy: Bool
    let onPicked: ([Data]) async -> Void

    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 4, matching: .images) {
            Image(systemName: "photo.on.rectangle")
        }
        .disabled(isBusy)
        .accessibilityLabel("写真を添付")
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            let picked = items
            // 同じ写真をもう一度選んだときも onChange が発火するよう、選択は毎回空に戻す
            selection = []
            Task {
                var datas: [Data] = []
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        datas.append(data)
                    }
                }
                await onPicked(datas)
            }
        }
    }
}
