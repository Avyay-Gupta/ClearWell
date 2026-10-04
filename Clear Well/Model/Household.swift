import Foundation

/// MN-06 counties, plus "Other".
enum County: String, Codable, CaseIterable, Identifiable {
    case carver, wright, sherburne, stearns, benton, anoka, hennepin, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .other: "Other"
        default: rawValue.capitalized
        }
    }

    /// "Wright County", or "Other county".
    var fullName: String { self == .other ? "Other county" : "\(name) County" }

    /// County seat, used to search for nearby labs in Maps.
    var countySeat: String? {
        switch self {
        case .carver: "Chaska"
        case .wright: "Buffalo"
        case .sherburne: "Elk River"
        case .stearns: "St. Cloud"
        case .benton: "Foley"
        case .anoka: "Anoka"
        case .hennepin: "Minneapolis"
        case .other: nil
        }
    }
}

enum WellAge: String, Codable, CaseIterable, Identifiable {
    case underTen, tenToTwentyFive, overTwentyFive, notSure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .underTen: "Less than 10 years"
        case .tenToTwentyFive: "10–25 years"
        case .overTwentyFive: "More than 25 years"
        case .notSure: "Not sure"
        }
    }
}

/// The three first-launch questions. This is what makes explanations personal.
struct HouseholdProfile: Codable, Equatable, Hashable {
    var infantOrPregnant: Bool = false
    var wellAge: WellAge = .notSure
    var county: County = .wright
}
