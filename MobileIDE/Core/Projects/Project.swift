import Foundation
import SwiftUI

/// PolePole の `~/Library/Application Support/polepole/projects.json`。
/// `{ schemaVersion: 1, projects: [...] }`。管理は PolePole 側で行い、こちらは読むだけ。
struct ProjectsFile: Decodable {
    var schemaVersion: Int
    var projects: [Project]
}

struct Project: Decodable, Identifiable, Hashable {
    var id: String
    var path: String
    var displayName: String
    var isPinned: Bool
    var lastOpenedAt: Date?
    var colorKey: String?

    var color: ProjectColor? { colorKey.flatMap(ProjectColor.init(rawValue:)) }

    init(id: String, path: String, displayName: String, isPinned: Bool = false, lastOpenedAt: Date? = nil, colorKey: String? = nil) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.isPinned = isPinned
        self.lastOpenedAt = lastOpenedAt
        self.colorKey = colorKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, displayName, isPinned, lastOpenedAt, colorKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            ?? URL(fileURLWithPath: path).lastPathComponent
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        colorKey = try c.decodeIfPresent(String.self, forKey: .colorKey)
    }

    static func decodeFile(_ data: Data) throws -> ProjectsFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectsFile.self, from: data)
    }
}

/// PolePole の `ProjectColor.swift` と同じ 10 色（RGB も同じ値）。
enum ProjectColor: String, CaseIterable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .red: return Color(red: 0.93, green: 0.34, blue: 0.34)
        case .orange: return Color(red: 0.95, green: 0.58, blue: 0.27)
        case .yellow: return Color(red: 0.92, green: 0.78, blue: 0.31)
        case .green: return Color(red: 0.42, green: 0.78, blue: 0.45)
        case .mint: return Color(red: 0.36, green: 0.82, blue: 0.71)
        case .teal: return Color(red: 0.31, green: 0.69, blue: 0.78)
        case .blue: return Color(red: 0.36, green: 0.60, blue: 0.93)
        case .indigo: return Color(red: 0.45, green: 0.47, blue: 0.86)
        case .purple: return Color(red: 0.66, green: 0.46, blue: 0.88)
        case .pink: return Color(red: 0.92, green: 0.45, blue: 0.69)
        }
    }
}
