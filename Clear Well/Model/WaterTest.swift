import Foundation

/// One measured value from a lab report, already converted to the unit in the limits table.
/// For coliform bacteria, 1 = present and 0 = absent.
struct Reading: Codable, Hashable {
    var contaminant: Contaminant
    var value: Double
}

/// A plain-English explanation for one contaminant.
struct Explanation: Codable, Hashable {
    enum Origin: String, Codable {
        case ai        // written by Claude through the ClearWell server
        case standard  // built on the phone from the limits table (used offline)
    }

    var text: String
    var nextStep: String
    var origin: Origin
}

/// One saved water test.
struct WaterTest: Identifiable, Codable, Hashable {
    enum Entry: String, Codable {
        case typed, scanned, demo
    }

    var id = UUID()
    var date: Date
    var county: County
    var labName: String?
    var readings: [Reading]
    var entry: Entry = .typed

    /// AI explanations, and the household they were written for (so a profile change triggers fresh ones).
    var explanations: [Contaminant: Explanation] = [:]
    var explainedFor: HouseholdProfile?

    func value(for contaminant: Contaminant) -> Double? {
        readings.first { $0.contaminant == contaminant }?.value
    }

    func status(for contaminant: Contaminant, profile: HouseholdProfile) -> WaterStatus? {
        guard let value = value(for: contaminant) else { return nil }
        return OfficialLimits.status(for: contaminant, value: value, infantOrPregnantAtHome: profile.infantOrPregnant)
    }

    /// Worst status in this test — what the Home card shows.
    func overallStatus(profile: HouseholdProfile) -> WaterStatus? {
        readings.compactMap { status(for: $0.contaminant, profile: profile) }.max()
    }

    /// Readings sorted red first, then amber, then green.
    func sortedReadings(profile: HouseholdProfile) -> [Reading] {
        readings.sorted { a, b in
            let sa = status(for: a.contaminant, profile: profile) ?? .green
            let sb = status(for: b.contaminant, profile: profile) ?? .green
            if sa != sb { return sa > sb }
            return Contaminant.allCases.firstIndex(of: a.contaminant)! < Contaminant.allCases.firstIndex(of: b.contaminant)!
        }
    }
}

extension Reading {
    /// "14.2 mg/L", or "Present" / "Absent" for bacteria.
    var formatted: String { Reading.format(value, for: contaminant) }

    static func format(_ value: Double, for contaminant: Contaminant) -> String {
        let limit = contaminant.limit
        if limit.kind == .presence { return value >= 1 ? "Present" : "Absent" }
        return "\(value.formatted(.number.precision(.fractionLength(0...3)))) \(limit.unit)"
    }
}
