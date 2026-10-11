import Foundation

/// Realistic sample data so the demo video always looks right.
/// A Wright County home with an infant, where nitrate has climbed over four years.
enum DemoData {
    static let profile = HouseholdProfile(waterSource: .privateWell, infantOrPregnant: true, wellAge: .overTwentyFive, county: .wright)

    /// A family of four with a water meter. They set a 10% goal six weeks ago and
    /// cut back — then use jumps in the last three days, the way a running toilet would.
    static func conservation(now: Date = .now) -> ConservationData {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }

        // (days covered, gallons per day), oldest first, ending today.
        let periods: [(Int, Double)] = [
            (7, 312), (7, 318), (7, 305), (7, 309), (7, 315), (7, 311), (7, 307),  // before the goal
            (7, 284), (7, 279), (7, 281), (7, 276), (7, 282),                      // after the goal
            (4, 290), (1, 405), (1, 418), (1, 426),                                // possible leak
        ]
        var reading = 48_210.0
        var day = periods.map(\.0).reduce(0, +)
        var entries = [UsageEntry(kind: .meterReading, date: daysAgo(day), amount: reading, unit: .gallons)]
        for (days, gallonsPerDay) in periods {
            reading += Double(days) * gallonsPerDay
            day -= days
            entries.append(UsageEntry(kind: .meterReading, date: daysAgo(day), amount: reading, unit: .gallons))
        }

        return ConservationData(
            entries: entries,
            habits: HouseholdHabits(people: 4, outdoorWatering: .often, olderToilets: .yes, olderShowerheads: .notSure),
            goal: ConservationGoal(reductionPercent: 10, baselineGallonsPerDay: 311, startDate: daysAgo(42)))
    }

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
