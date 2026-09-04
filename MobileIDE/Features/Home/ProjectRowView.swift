import SwiftUI

/// 一覧の 1 行。色の丸、名前、path、セッションの状態。
struct ProjectRowView: View {
    let row: ProjectListModel.Row
    /// path の先頭をこれに置き換えて `~/…` と短く見せる（リモートのホーム）
    let homePath: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(row.project.color?.color ?? Color.secondary.opacity(0.4))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.project.displayName)
                Text(shortPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            badge
        }
        .contentShape(Rectangle())
    }

    private var shortPath: String {
        let path = row.project.path
        if !homePath.isEmpty, path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    @ViewBuilder
    private var badge: some View {
        switch row.sessionState {
        case .none:
            EmptyView()
        case .alive:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
                .accessibilityLabel("セッションあり")
        case .attached:
            Label("接続中", systemImage: "iphone")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        }
    }
}
