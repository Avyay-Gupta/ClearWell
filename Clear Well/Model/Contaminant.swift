import Foundation

/// The contaminants ClearWell tracks. Each one has a matching row in `OfficialLimits.table`.
enum Contaminant: String, CaseIterable, Codable, Identifiable, Hashable {
    case nitrate
    case arsenic
    case lead
    case manganese
    case fluoride
    case coliform

    var id: String { rawValue }

    /// This contaminant's row in the official limits table.
    var limit: OfficialLimit { OfficialLimits.limit(for: self) }

    var name: String { limit.name }
}

/// Green / amber / red. Comes ONLY from `OfficialLimits.status(...)` — never from the AI.
enum WaterStatus: Int, Codable, Comparable, CaseIterable {
    case green = 0
    case amber = 1
    case red = 2

    static func < (lhs: WaterStatus, rhs: WaterStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What the status means in plain words.
    var title: String {
        switch self {
        case .green: "Looks good"
        case .amber: "Check soon"
        case .red: "Act now"
        }
    }

    /// Shape icon, so status never relies on color alone.
    var symbol: String {
        switch self {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.triangle.fill"
        case .red: "xmark.octagon.fill"
        }
    }
}
