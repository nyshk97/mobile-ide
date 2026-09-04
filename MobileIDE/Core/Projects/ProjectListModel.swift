import Foundation
import Observation

/// ホームの一覧の状態。取得（ProjectListLoader）と表示（HomeView）の間。
@Observable
@MainActor
final class ProjectListModel {
    enum SessionState: Hashable {
        /// tmux にセッションが無い
        case none
        /// セッションはあるがクライアントは付いていない
        case alive
        /// 誰か（この iPhone を含む）が attach 中
        case attached
    }

    struct Row: Identifiable, Hashable {
        var project: Project
        var sessionName: String
        var sessionState: SessionState
        var id: String { project.id }

        var target: TerminalTarget {
            TerminalTarget(sessionName: sessionName, workingDirectory: project.path)
        }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(ConnectFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var pinned: [Row] = []
    private(set) var others: [Row] = []

    var isEmpty: Bool { pinned.isEmpty && others.isEmpty }
    var allRows: [Row] { pinned + others }

    func refresh(settings: ConnectionSettings, identity: SSHIdentity, knownHosts: KnownHostStore) async {
        if case .loading = phase { return }
        phase = .loading
        do {
            let fetched = try await ProjectListLoader.fetch(settings: settings, identity: identity, knownHosts: knownHosts)
            apply(fetched)
            phase = .loaded(Date())
            let alive = allRows.filter { $0.sessionState != .none }.map(\.sessionName)
            print("PROJECTS loaded pinned=\(pinned.count) others=\(others.count) alive=\(alive.joined(separator: ","))")
        } catch let failure as ConnectFailure {
            phase = .failed(failure)
            print("PROJECTS failed \(failure.description)".replacingOccurrences(of: "\n", with: " "))
        } catch {
            phase = .failed(.other("\(error)"))
            print("PROJECTS failed \(error)")
        }
    }

    /// 取得結果を行に組み立てる。ピン留めは配列順（= PolePole のピン順）、その他は lastOpenedAt 降順
    func apply(_ fetched: ProjectListLoader.Fetched) {
        let projects = fetched.file.projects
        let names = TmuxSessionName.names(forPaths: projects.map(\.path))
        let sessions = Dictionary(fetched.sessions.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        func row(_ project: Project) -> Row {
            let name = names[project.path] ?? TmuxSessionName.sanitize(project.displayName)
            let state: SessionState
            if let session = sessions[name] {
                state = session.attached > 0 ? .attached : .alive
            } else {
                state = .none
            }
            return Row(project: project, sessionName: name, sessionState: state)
        }
        pinned = projects.filter(\.isPinned).map(row)
        others = projects.filter { !$0.isPinned }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .map(row)
    }
}
