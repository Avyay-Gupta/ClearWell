import Foundation

/// Realistic sample data so the demo video always looks right.
/// A Wright County home with an infant, where nitrate has climbed over four years.
enum DemoData {
    static let profile = HouseholdProfile(infantOrPregnant: true, wellAge: .overTwentyFive, county: .wright)

    static func tests(now: Date = .now) -> [WaterTest] {
        let calendar = Calendar.current
        func monthsAgo(_ months: Int) -> Date {
            calendar.date(byAdding: .month, value: -months, to: now) ?? now
        }

        return [
            WaterTest(
                date: monthsAgo(1),
                county: .wright,
                labName: "Sample Environmental Lab",
                readings: [
                    Reading(contaminant: .nitrate, value: 14.2),
                    Reading(contaminant: .arsenic, value: 3.8),
                    Reading(contaminant: .manganese, value: 140),
                    Reading(contaminant: .lead, value: 0),
                    Reading(contaminant: .fluoride, value: 0.4),
                    Reading(contaminant: .coliform, value: 0),
                ],
                entry: .demo),
            WaterTest(
                date: monthsAgo(13),
                county: .wright,
                labName: "Sample Environmental Lab",
                readings: [
                    Reading(contaminant: .nitrate, value: 9.1),
                    Reading(contaminant: .coliform, value: 0),
                    Reading(contaminant: .manganese, value: 120),
                ],
                entry: .demo),
            WaterTest(
                date: monthsAgo(25),
                county: .wright,
                labName: "Sample Environmental Lab",
                readings: [
                    Reading(contaminant: .nitrate, value: 6.4),
                    Reading(contaminant: .coliform, value: 0),
                ],
                entry: .demo),
            WaterTest(
                date: monthsAgo(49),
                county: .wright,
                labName: "Sample Environmental Lab",
                readings: [
                    Reading(contaminant: .nitrate, value: 4.1),
                    Reading(contaminant: .arsenic, value: 3.2),
                    Reading(contaminant: .coliform, value: 0),
                ],
                entry: .demo),
        ]
    }
}
