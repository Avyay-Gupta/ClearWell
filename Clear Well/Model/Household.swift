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

/// Where the home's water comes from. Conservation and community tools work for both.
enum WaterSource: String, Codable, CaseIterable, Identifiable {
    case privateWell, municipal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .privateWell: "Private well"
        case .municipal: "City or community water"
        }
    }
}

/// The first-launch questions. This is what makes explanations personal.
struct HouseholdProfile: Codable, Equatable, Hashable {
    var waterSource: WaterSource = .privateWell
    var infantOrPregnant: Bool = false
    var wellAge: WellAge = .notSure
    var county: County = .wright

    var hasPrivateWell: Bool { waterSource == .privateWell }

    enum CodingKeys: String, CodingKey {
        case waterSource, infantOrPregnant, wellAge, county
    }
}

extension HouseholdProfile {
    /// Older saved data has no water source; those households were all private-well users.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waterSource = try container.decodeIfPresent(WaterSource.self, forKey: .waterSource) ?? .privateWell
        infantOrPregnant = try container.decode(Bool.self, forKey: .infantOrPregnant)
        wellAge = try container.decode(WellAge.self, forKey: .wellAge)
        county = try container.decode(County.self, forKey: .county)
    }
}

extension County {
    /// Federal county code, used to ask public data services about this county.
    var fips: String? {
        switch self {
        case .anoka: "27003"
        case .benton: "27009"
        case .carver: "27019"
        case .hennepin: "27053"
        case .sherburne: "27141"
        case .stearns: "27145"
        case .wright: "27171"
        case .other: nil
        }
    }

    /// Approximate location of the county seat, for the weather forecast.
    var seatCoordinate: (latitude: Double, longitude: Double)? {
        switch self {
        case .carver: (44.7889, -93.6022)     // Chaska
        case .wright: (45.1719, -93.8747)     // Buffalo
        case .sherburne: (45.3036, -93.5672)  // Elk River
        case .stearns: (45.5608, -94.1622)    // St. Cloud
        case .benton: (45.6647, -93.9100)     // Foley
        case .anoka: (45.1977, -93.3872)      // Anoka
        case .hennepin: (44.9778, -93.2650)   // Minneapolis
        case .other: nil
        }
    }
}
