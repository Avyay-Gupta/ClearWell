import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  HOUSEHOLD WATER CONSERVATION
//
//  Usage comes only from what the household enters: meter readings or water
//  bills. All math here is plain arithmetic — the AI only suggests ideas.
//  Measured numbers (from the meter or bills) are kept separate from
//  estimates (published averages), and estimates are always labeled.
// ─────────────────────────────────────────────────────────────────────────────

enum UsageUnit: String, Codable, CaseIterable, Identifiable {
    case gallons, cubicFeet, hundredCubicFeet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gallons: "Gallons"
        case .cubicFeet: "Cubic feet"
        case .hundredCubicFeet: "CCF (100 cubic feet)"
        }
    }

    var short: String {
        switch self {
        case .gallons: "gal"
        case .cubicFeet: "ft³"
        case .hundredCubicFeet: "CCF"
        }
    }

    /// 1 cubic foot = 7.48052 U.S. gallons.
    var gallonsPerUnit: Double {
        switch self {
        case .gallons: 1
        case .cubicFeet: 7.48052
        case .hundredCubicFeet: 748.052
        }
    }
}

/// One thing the household entered: a meter reading, or the usage on a water bill.
struct UsageEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case meterReading, bill
    }

    var id = UUID()
    var kind: Kind
    /// Reading date, or the last day of the bill period.
    var date: Date
    /// First day of the bill period (bills only).
    var startDate: Date?
    /// The meter's total reading, or the amount used on the bill.
    var amount: Double
    var unit: UsageUnit

    var gallons: Double { amount * unit.gallonsPerUnit }
}

/// Water used between two points in time.
struct UsageInterval: Identifiable, Equatable {
    var start: Date
    var end: Date
    var gallons: Double
    var source: UsageEntry.Kind

    var id: Date { end }
    var days: Double { end.timeIntervalSince(start) / 86_400 }
    var gallonsPerDay: Double { gallons / days }
}

/// Usage in one window compared with the window before it.
struct UsageComparison: Identifiable, Equatable {
    var label: String          // "Day", "Week", "Month"
    var current: Double        // average gallons per day
    var previous: Double
    var id: String { label }

    var percentChange: Double { previous > 0 ? (current - previous) / previous * 100 : 0 }
}

/// A period that used noticeably more water than usual.
struct UnusualUsage: Equatable {
    var interval: UsageInterval
    var baselineGallonsPerDay: Double

    var extraGallonsPerDay: Double { interval.gallonsPerDay - baselineGallonsPerDay }
    var percentAbove: Double { extraGallonsPerDay / baselineGallonsPerDay * 100 }
}

struct ConservationGoal: Codable, Equatable {
    var reductionPercent: Int
    var baselineGallonsPerDay: Double
    var startDate: Date

    var targetGallonsPerDay: Double { baselineGallonsPerDay * (1 - Double(reductionPercent) / 100) }
}

struct GoalProgress: Equatable {
    var currentGallonsPerDay: Double
    var measuredDays: Double
    /// Gallons saved compared with the baseline, measured from meter readings or bills.
    var measuredGallonsSaved: Double
    var onTrack: Bool
}

enum UsageAnalysis {
    /// Changes need to be at least this large (and this many gallons/day) to be flagged.
    static let unusualPercent = 30.0
    static let unusualMinimumGallonsPerDay = 25.0
    /// A comparison window must be at least this fully covered by readings.
    static let requiredCoverage = 0.9

    /// Turns readings and bills into periods of use, oldest first.
    static func intervals(from entries: [UsageEntry]) -> [UsageInterval] {
        var result: [UsageInterval] = []

        let readings = entries.filter { $0.kind == .meterReading }.sorted { $0.date < $1.date }
        for (earlier, later) in zip(readings, readings.dropFirst()) {
            let used = later.gallons - earlier.gallons
            let hours = later.date.timeIntervalSince(earlier.date) / 3600
            // A lower reading means the meter was replaced or rolled over: skip that gap.
            guard used >= 0, hours >= 1 else { continue }
            result.append(UsageInterval(start: earlier.date, end: later.date, gallons: used, source: .meterReading))
        }

        for bill in entries where bill.kind == .bill {
            guard let start = bill.startDate, bill.date > start, bill.gallons >= 0 else { continue }
            result.append(UsageInterval(start: start, end: bill.date, gallons: bill.gallons, source: .bill))
        }

        return result.sorted { $0.end < $1.end }
    }

    /// Average gallons per day across `range`, or nil if the readings don't cover enough of it.
    static func averageGallonsPerDay(in range: Range<Date>, intervals: [UsageInterval]) -> Double? {
        let rangeDays = range.upperBound.timeIntervalSince(range.lowerBound) / 86_400
        guard rangeDays > 0 else { return nil }
        var coveredDays = 0.0
        var gallons = 0.0
        for interval in intervals {
            let start = max(interval.start, range.lowerBound)
            let end = min(interval.end, range.upperBound)
            guard end > start else { continue }
            let overlapDays = end.timeIntervalSince(start) / 86_400
            coveredDays += overlapDays
            gallons += interval.gallonsPerDay * overlapDays
        }
        guard coveredDays >= rangeDays * requiredCoverage else { return nil }
        return gallons / coveredDays
    }

    /// Day, week and month comparisons, counted back from the newest reading.
    /// Only comparisons with enough data on both sides are returned, and only readings
    /// spaced about as closely as the window are used — a weekly reading can't tell
    /// one day from the next.
    static func comparisons(_ intervals: [UsageInterval]) -> [UsageComparison] {
        guard let latest = intervals.map(\.end).max() else { return [] }
        let windows: [(String, Double)] = [("Day", 1), ("Week", 7), ("Month", 30)]
        return windows.compactMap { label, days in
            let usable = intervals.filter { $0.days <= days * 1.5 }
            let length = days * 86_400
            let currentRange = latest.addingTimeInterval(-length)..<latest
            let previousRange = latest.addingTimeInterval(-2 * length)..<latest.addingTimeInterval(-length)
            guard let current = averageGallonsPerDay(in: currentRange, intervals: usable),
                  let previous = averageGallonsPerDay(in: previousRange, intervals: usable) else { return nil }
            return UsageComparison(label: label, current: current, previous: previous)
        }
    }

    /// Typical use before the newest period: the median of earlier periods' daily averages.
    static func baselineGallonsPerDay(_ intervals: [UsageInterval]) -> Double? {
        median(intervals.dropLast().map(\.gallonsPerDay))
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Flags the newest period if it used much more than usual (a possible leak).
    /// Needs at least two earlier periods to know what "usual" is.
    static func unusualUsage(_ intervals: [UsageInterval]) -> UnusualUsage? {
        guard intervals.count >= 3, let latest = intervals.last,
              let baseline = baselineGallonsPerDay(intervals), baseline > 0 else { return nil }
        let result = UnusualUsage(interval: latest, baselineGallonsPerDay: baseline)
        guard result.percentAbove >= unusualPercent, result.extraGallonsPerDay >= unusualMinimumGallonsPerDay else { return nil }
        return result
    }

    /// The starting point for a new goal: last 30 days if covered, otherwise typical use.
    static func goalBaseline(_ intervals: [UsageInterval]) -> Double? {
        if let latest = intervals.map(\.end).max(),
           let month = averageGallonsPerDay(in: latest.addingTimeInterval(-30 * 86_400)..<latest, intervals: intervals) {
            return month
        }
        return median(intervals.map(\.gallonsPerDay))
    }

    /// How the household is doing since the goal started, measured from its own readings.
    static func progress(of goal: ConservationGoal, intervals: [UsageInterval]) -> GoalProgress? {
        var days = 0.0
        var gallons = 0.0
        for interval in intervals where interval.end > goal.startDate {
            let start = max(interval.start, goal.startDate)
            let overlap = interval.end.timeIntervalSince(start) / 86_400
            guard overlap > 0 else { continue }
            days += overlap
            gallons += interval.gallonsPerDay * overlap
        }
        guard days >= 1 else { return nil }
        let current = gallons / days
        return GoalProgress(
            currentGallonsPerDay: current,
            measuredDays: days,
            measuredGallonsSaved: max(0, (goal.baselineGallonsPerDay - current) * days),
            onTrack: current <= goal.targetGallonsPerDay)
    }
}

// MARK: - Habits and recommendations

enum OutdoorWatering: String, Codable, CaseIterable, Identifiable {
    case none, sometimes, often, automaticSprinklers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "We don't water outdoors"
        case .sometimes: "Sometimes, with a hose"
        case .often: "Often, with a hose or sprinkler"
        case .automaticSprinklers: "Automatic sprinkler system"
        }
    }
}

enum YesNoUnsure: String, Codable, CaseIterable, Identifiable {
    case yes, no, notSure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }
}

struct HouseholdHabits: Codable, Equatable, Hashable {
    var people: Int = 3
    var outdoorWatering: OutdoorWatering = .sometimes
    var olderToilets: YesNoUnsure = .notSure
    var olderShowerheads: YesNoUnsure = .notSure
}

/// A conservation idea. Savings are always estimates, never measurements.
struct Recommendation: Identifiable, Codable, Hashable {
    enum Origin: String, Codable { case ai, standard }

    var id: String
    var title: String
    var detail: String
    /// Estimated yearly savings, or nil when there's no reliable published estimate.
    var estimatedGallonsPerYear: Double?
    /// Where the estimate comes from and why it's uncertain.
    var estimateBasis: String?
    var origin: Origin
}

enum Season: String, Codable {
    case spring, summer, fall, winter

    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.month, from: date) {
        case 3...5: self = .spring
        case 6...8: self = .summer
        case 9...11: self = .fall
        default: self = .winter
        }
    }

    var outdoorWateringSeason: Bool { self == .spring || self == .summer }
}

/// Published U.S. EPA WaterSense figures. The AI may only use these numbers.
/// Source: https://www.epa.gov/watersense/statistics-and-facts (checked Oct 2026).
enum WaterSenseFacts {
    static let gallonsPerPersonPerDay = 82.0
    static let householdLeaksPerYear = 9_400.0
    static let olderToiletsPerYear = 13_000.0
    static let showerheadsPerYear = 2_700.0
    static let irrigationControllerPerYear = 15_000.0
    static let fullDishwasherPerYear = 320.0
    static let tapOffPerPersonPerYear = 5_700.0
    static let source = URL(string: "https://www.epa.gov/watersense/statistics-and-facts")!

    /// Facts sent to the AI so its savings estimates stay grounded.
    static let referenceList: [(id: String, gallonsPerYear: Double, fact: String)] = [
        ("leaks", householdLeaksPerYear, "The average family can waste 9,400 gallons a year from household leaks."),
        ("toilets", olderToiletsPerYear, "Replacing all old, inefficient toilets with WaterSense models saves the average family about 13,000 gallons a year."),
        ("showerheads", showerheadsPerYear, "Replacing showerheads with WaterSense models saves the average family more than 2,700 gallons a year."),
        ("irrigation", irrigationControllerPerYear, "A WaterSense irrigation controller can save an average home up to 15,000 gallons a year (up to 30% of irrigation)."),
        ("dishwasher", fullDishwasherPerYear, "Running the dishwasher only when full saves the average family nearly 320 gallons a year."),
        ("tap", tapOffPerPersonPerYear, "Turning off the tap while brushing teeth (twice a day) and shaving (5 times a week) saves nearly 5,700 gallons a year per person."),
    ]
}

/// Rule-based ideas built on the phone. Used instantly and whenever the AI is unavailable.
enum StandardRecommendations {
    static func make(habits: HouseholdHabits, unusual: UnusualUsage?, season: Season, inDrought: Bool) -> [Recommendation] {
        let basis = "EPA WaterSense estimate for an average family. Your savings depend on your home and habits."
        var list: [Recommendation] = []

        if unusual != nil {
            list.append(Recommendation(
                id: "leak-check",
                title: "Check for a leak now",
                detail: "Your newest reading is well above your usual use. Turn off every faucet and appliance, then watch your meter for an hour. If it moves, something is leaking — often a running toilet or a dripping faucet.",
                estimatedGallonsPerYear: WaterSenseFacts.householdLeaksPerYear,
                estimateBasis: "EPA WaterSense: the average family can waste 9,400 gallons a year from leaks. Your leak could be bigger or smaller.",
                origin: .standard))
        }
        if habits.olderToilets != .no {
            list.append(Recommendation(
                id: "toilets",
                title: "Replace older toilets",
                detail: "Toilets are the biggest indoor water user. WaterSense-labeled models use much less per flush.",
                estimatedGallonsPerYear: WaterSenseFacts.olderToiletsPerYear,
                estimateBasis: basis,
                origin: .standard))
        }
        if habits.olderShowerheads != .no {
            list.append(Recommendation(
                id: "showerheads",
                title: "Switch to WaterSense showerheads",
                detail: "A low-cost swap that also cuts the energy used to heat water.",
                estimatedGallonsPerYear: WaterSenseFacts.showerheadsPerYear,
                estimateBasis: basis,
                origin: .standard))
        }
        if habits.outdoorWatering != .none {
            if season.outdoorWateringSeason {
                list.append(Recommendation(
                    id: "lawn",
                    title: inDrought ? "Water less during the drought" : "Water the lawn deeply, less often",
                    detail: inDrought
                        ? "University of Minnesota Extension suggests about 1 inch of water every 10 to 14 days for established lawns during drought, in the morning."
                        : "University of Minnesota Extension suggests watering once a week or less, in the morning, with enough to soak the soil about 6 inches deep.",
                    estimatedGallonsPerYear: habits.outdoorWatering == .automaticSprinklers ? WaterSenseFacts.irrigationControllerPerYear : nil,
                    estimateBasis: habits.outdoorWatering == .automaticSprinklers
                        ? "EPA WaterSense: a WaterSense irrigation controller can save an average home up to 15,000 gallons a year. \"Up to\" means many homes save less."
                        : nil,
                    origin: .standard))
            } else if season == .fall {
                list.append(Recommendation(
                    id: "winterize",
                    title: "Winterize outdoor water",
                    detail: "Disconnect hoses and shut off outdoor faucets before freezing weather so pipes don't crack and leak.",
                    estimatedGallonsPerYear: nil,
                    estimateBasis: nil,
                    origin: .standard))
            }
        }
        list.append(Recommendation(
            id: "dishwasher",
            title: "Run the dishwasher only when it's full",
            detail: "Skipping one half-empty load a week adds up over a year.",
            estimatedGallonsPerYear: WaterSenseFacts.fullDishwasherPerYear,
            estimateBasis: basis,
            origin: .standard))
        list.append(Recommendation(
            id: "tap",
            title: "Turn off the tap while brushing",
            detail: "The faucet doesn't need to run while you brush or shave.",
            estimatedGallonsPerYear: WaterSenseFacts.tapOffPerPersonPerYear * Double(max(habits.people, 1)),
            estimateBasis: "EPA WaterSense: nearly 5,700 gallons a year per person who brushes twice a day and shaves 5 times a week, times \(max(habits.people, 1)) people. Most households save less.",
            origin: .standard))
        return list
    }
}

/// Everything the Conserve tab saves on the phone.
struct ConservationData: Codable, Equatable {
    var entries: [UsageEntry] = []
    var habits = HouseholdHabits()
    var goal: ConservationGoal?
    /// The most recent AI suggestions and what they were written for.
    var aiRecommendations: [Recommendation] = []
    var aiRecommendationsKey: String?
}
