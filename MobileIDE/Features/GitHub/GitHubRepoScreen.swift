import Observation
import SwiftUI

/// 「GitHub から追加」の状態
@Observable
@MainActor
final class GitHubRepoModel {
    struct Row: Identifiable, Hashable {
        var repo: GitHubRepo
        /// ホストにある clone のパス（origin が一致したもの）。無ければ未 clone
        var localPath: String?
        var id: String { repo.id }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(ConnectFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var rows: [Row] = []
    /// clone 中の repo（同時に 1 件だけ）
    private(set) var cloning: String?
    var cloneError: String?

    func refresh(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async {
        if case .loading = phase { return }
        phase = .loading
        do {
            let fetched = try await GitHubRepoLoader.fetch(settings: settings, identity: identity, knownHosts: knownHosts)
            rows = Self.rows(fetched)
            phase = .loaded
            print("GITHUB loaded total=\(rows.count) cloned=\(rows.filter { $0.localPath != nil }.count)")
        } catch let failure as ConnectFailure {
            phase = .failed(failure)
            print("GITHUB failed \(failure.description)".replacingOccurrences(of: "\n", with: " "))
        } catch {
            phase = .failed(.other("\(error)"))
            print("GITHUB failed \(error)")
        }
    }

    /// 同じ repo の clone が複数あれば浅いパス（`~/x` を `~/dm/x` より先）を採る
    static func rows(_ fetched: GitHubRepoLoader.Fetched) -> [Row] {
        var local: [String: String] = [:]
        for repo in fetched.local.sorted(by: { $0.path.count < $1.path.count }) {
            if let slug = repo.slug, local[slug] == nil { local[slug] = repo.path }
        }
        return fetched.repos.map { Row(repo: $0, localPath: local[$0.slug]) }
    }

    /// 成功したら clone 先のパスを返す
    func clone(_ row: Row, settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async -> String? {
        guard cloning == nil else { return nil }
        cloning = row.id
        defer { cloning = nil }
        do {
            switch try await GitHubRepoLoader.clone(row.repo, settings: settings, identity: identity, knownHosts: knownHosts) {
            case .cloned(let path):
                print("GITHUB clone ok path=\(path)")
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].localPath = path }
                return path
            case .alreadyExists(let path):
                print("GITHUB clone failed exists path=\(path)")
                cloneError = "\(path) が既にあります。別のリポジトリか、git 管理でないディレクトリです。Mac で確認してください"
            case .failed(let output):
                print("GITHUB clone failed \(output)".replacingOccurrences(of: "\n", with: " "))
                cloneError = output
            }
        } catch {
            print("GITHUB clone failed \(error)")
            cloneError = "\(error)"
        }
        return nil
    }
}

/// ホストの GitHub リポジトリ一覧。未 clone をタップすると `~/<name>` に clone して端末を開き、clone 済みはそのまま開く
struct GitHubRepoScreen: View {
    /// ホームの一覧に出ている全パス。セッション名をホームと揃えるのに使う
    let knownPaths: [String]
    let open: (TerminalTarget) -> Void

    @Environment(ConnectionSettings.self) private var settings
    @Environment(SSHIdentity.self) private var identity
    @Environment(KnownHostStore.self) private var knownHosts

    @State private var model = GitHubRepoModel()
    @State private var query = ""
    @State private var autoCloned = false

    var body: some View {
        List {
            switch model.phase {
            case .idle, .loading:
                if model.rows.isEmpty {
                    HStack { ProgressView(); Text("GitHub から読み込み中…").foregroundStyle(.secondary) }
                }
            case .failed(let failure):
                VStack(alignment: .leading, spacing: 8) {
                    Label("一覧を取得できませんでした", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(failure.description)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("再試行") { Task { await refresh() } }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            case .loaded:
                EmptyView()
            }
            ForEach(filtered) { row in
                // .plain にしないと行全体が tint の青になる（ホームの行と配色を揃える）
                Button { Task { await tap(row) } } label: { rowView(row) }
                    .buttonStyle(.plain)
                    .disabled(model.cloning != nil)
            }
        }
        .navigationTitle("GitHub から追加")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "リポジトリ名")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await refresh() }
        .task { if model.phase == .idle { await refresh() } }
        .alert("clone できませんでした", isPresented: Binding(
            get: { model.cloneError != nil },
            set: { if !$0 { model.cloneError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.cloneError ?? "")
        }
    }

    private var filtered: [GitHubRepoModel.Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.rows }
        return model.rows.filter { $0.repo.slug.contains(q) }
    }

    private func rowView(_ row: GitHubRepoModel.Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.repo.name).foregroundStyle(.primary)
                    if row.repo.isPrivate {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(row.localPath.map(shortPath) ?? row.repo.nameWithOwner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if model.cloning == row.id {
                ProgressView()
            } else if row.localPath == nil {
                Label("未 clone", systemImage: "icloud.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
            }
        }
        .contentShape(Rectangle())
    }

    private func shortPath(_ path: String) -> String {
        let home = "/Users/\(settings.user)"
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func refresh() async {
        await model.refresh(settings: settings, identity: identity, knownHosts: knownHosts)
        // 自走検証: MOBILE_IDE_CLONE_REPO=<owner/name> の行を自動でタップ
        if !autoCloned, let slug = LaunchOptions.cloneRepo?.lowercased(),
           let row = model.rows.first(where: { $0.repo.slug == slug }) {
            autoCloned = true
            await tap(row)
        }
    }

    private func tap(_ row: GitHubRepoModel.Row) async {
        var path = row.localPath
        if path == nil {
            path = await model.clone(row, settings: settings, identity: identity, knownHosts: knownHosts)
        }
        guard let path else { return }
        open(Self.target(path: path, knownPaths: knownPaths))
    }

    /// ホームと同じ規則（全パスの集合で決まる）でセッション名を付ける
    static func target(path: String, knownPaths: [String]) -> TerminalTarget {
        let paths = knownPaths.contains(path) ? knownPaths : knownPaths + [path]
        let name = TmuxSessionName.names(forPaths: paths)[path]
            ?? TmuxSessionName.sanitize(URL(fileURLWithPath: path).lastPathComponent)
        return TerminalTarget(sessionName: name, workingDirectory: path)
    }
}
