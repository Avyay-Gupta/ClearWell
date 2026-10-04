import Foundation

/// When each contaminant should be tested next, using MDH's schedule from the limits table.
enum TestingSchedule {
    struct Due: Identifiable, Equatable {
        var contaminant: Contaminant
        /// The date the next test is due. Past dates mean "due now".
        var date: Date
        var neverTested: Bool

        var id: Contaminant { contaminant }
    }

    /// Next due date for one contaminant, or `nil` if no further test is needed
    /// (an "at least once" contaminant that has already been tested).
    static func nextDue(for contaminant: Contaminant, tests: [WaterTest], now: Date = .now, calendar: Calendar = .current) -> Due? {
        let lastTested = tests
            .filter { $0.value(for: contaminant) != nil }
            .map(\.date)
            .max()

        guard let lastTested else {
            return Due(contaminant: contaminant, date: now, neverTested: true)
        }

        switch contaminant.limit.retest {
        case .atLeastOnce:
            return nil
        case .everyYears(let years):
            let date = calendar.date(byAdding: .year, value: years, to: lastTested) ?? lastTested
            return Due(contaminant: contaminant, date: date, neverTested: false)
        }
    }

    /// Everything that is due, soonest first.
    static func upcoming(tests: [WaterTest], now: Date = .now) -> [Due] {
        Contaminant.allCases
            .compactMap { nextDue(for: $0, tests: tests, now: now) }
            .sorted { $0.date < $1.date }
    }

    /// "now", "in 4 months", "in 12 days".
    static func relativeDescription(of date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        if date <= startOfToday { return "now" }
        let parts = calendar.dateComponents([.month, .day], from: startOfToday, to: calendar.startOfDay(for: date))
        let months = parts.month ?? 0
        let days = parts.day ?? 0
        if months >= 1 {
            return months == 1 ? "in 1 month" : "in \(months) months"
        }
        if days <= 1 { return "tomorrow" }
        return "in \(days) days"
    }
}
