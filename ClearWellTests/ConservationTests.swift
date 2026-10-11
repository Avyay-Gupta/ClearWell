import Foundation
import Testing
@testable import Clear_Well

@MainActor
struct ConservationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    /// Meter readings taken every `step` days at the given gallons per day.
    private func readings(_ rates: [Double], step: Double = 7, unit: UsageUnit = .gallons) -> [UsageEntry] {
        var total = 10_000.0
        var entries = [UsageEntry(kind: .meterReading, date: day(0), amount: total / unit.gallonsPerUnit, unit: unit)]
        for (index, rate) in rates.enumerated() {
            total += rate * step
            entries.append(UsageEntry(kind: .meterReading, date: day(Double(index + 1) * step), amount: total / unit.gallonsPerUnit, unit: unit))
        }
        return entries
    }

    @Test("Meter readings become periods of use")
    func intervalsFromReadings() {
        let intervals = UsageAnalysis.intervals(from: readings([300, 280]))
        #expect(intervals.count == 2)
        #expect(abs(intervals[0].gallonsPerDay - 300) < 0.001)
        #expect(abs(intervals[1].gallons - 1_960) < 0.001)
    }

    @Test("Cubic-foot readings are converted to gallons")
    func cubicFeet() {
        let intervals = UsageAnalysis.intervals(from: readings([300], unit: .cubicFeet))
        #expect(abs(intervals[0].gallonsPerDay - 300) < 0.01)
    }

    @Test("A lower reading (replaced meter) is skipped, not counted as negative use")
    func meterReplaced() {
        let entries = [
            UsageEntry(kind: .meterReading, date: day(0), amount: 5_000, unit: .gallons),
            UsageEntry(kind: .meterReading, date: day(7), amount: 7_000, unit: .gallons),
            UsageEntry(kind: .meterReading, date: day(14), amount: 100, unit: .gallons),
        ]
        #expect(UsageAnalysis.intervals(from: entries).count == 1)
    }

    @Test("Water bills become periods of use")
    func bills() {
        let bill = UsageEntry(kind: .bill, date: day(30), startDate: day(0), amount: 12, unit: .hundredCubicFeet)
        let interval = UsageAnalysis.intervals(from: [bill])[0]
        #expect(abs(interval.gallons - 8_976.624) < 0.01)
        #expect(abs(interval.gallonsPerDay - 299.22) < 0.01)
    }

    @Test("Week comparison appears only with two full weeks of data")
    func comparisons() {
        #expect(UsageAnalysis.comparisons(UsageAnalysis.intervals(from: readings([300]))).isEmpty)
        let two = UsageAnalysis.comparisons(UsageAnalysis.intervals(from: readings([300, 270])))
        let week = two.first { $0.label == "Week" }
        #expect(week != nil)
        #expect(abs((week?.percentChange ?? 0) + 10) < 0.001)
        #expect(two.first { $0.label == "Month" } == nil)
    }

    @Test("A big jump over usual use is flagged as a possible leak")
    func leakFlag() {
        let unusual = UsageAnalysis.unusualUsage(UsageAnalysis.intervals(from: readings([300, 310, 295, 420])))
        #expect(unusual != nil)
        #expect(abs((unusual?.baselineGallonsPerDay ?? 0) - 300) < 0.001)
    }

    @Test("Normal ups and downs are not flagged")
    func noLeakFlag() {
        #expect(UsageAnalysis.unusualUsage(UsageAnalysis.intervals(from: readings([300, 310, 295, 330]))) == nil)
        // Not enough history to know what's usual.
        #expect(UsageAnalysis.unusualUsage(UsageAnalysis.intervals(from: readings([300, 600]))) == nil)
    }

    @Test("Goal progress is measured from readings after the goal started")
    func goalProgress() {
        let intervals = UsageAnalysis.intervals(from: readings([300, 300, 260, 260]))
        let goal = ConservationGoal(reductionPercent: 10, baselineGallonsPerDay: 300, startDate: day(14))
        let progress = UsageAnalysis.progress(of: goal, intervals: intervals)
        #expect(progress?.onTrack == true)
        #expect(abs((progress?.measuredGallonsSaved ?? 0) - 560) < 0.001)
        #expect(abs(goal.targetGallonsPerDay - 270) < 0.001)
    }

    @Test("Standard tips always label savings as estimates with a basis")
    func standardTips() {
        let tips = StandardRecommendations.make(habits: HouseholdHabits(), unusual: nil, season: .summer, inDrought: true)
        #expect(!tips.isEmpty)
        for tip in tips where tip.estimatedGallonsPerYear != nil {
            #expect(tip.estimateBasis != nil, "\(tip.title) needs an estimate basis")
        }
        #expect(tips.contains { $0.id == "lawn" && $0.title.contains("drought") })
    }

    @Test("Lawn tips only in spring and summer; fall suggests winterizing")
    func seasonalTips() {
        let fall = StandardRecommendations.make(habits: HouseholdHabits(), unusual: nil, season: .fall, inDrought: false)
        #expect(!fall.contains { $0.id == "lawn" })
        #expect(fall.contains { $0.id == "winterize" })
    }

    @Test("Challenge savings are measured against the 30 days before it started")
    func challengeSavings() {
        // 30 days at 300 gal/day, then 10 days at 270 gal/day.
        let entries = [
            UsageEntry(kind: .meterReading, date: day(0), amount: 0, unit: .gallons),
            UsageEntry(kind: .meterReading, date: day(30), amount: 9_000, unit: .gallons),
            UsageEntry(kind: .meterReading, date: day(40), amount: 11_700, unit: .gallons),
        ]
        let formatter = Challenge.dayFormatter
        let challenge = Challenge(
            id: "test", title: "Test", summary: "", whyItMatters: "",
            startDate: formatter.string(from: day(30)), endDate: formatter.string(from: day(60)),
            measuredByMeter: true, actions: [], participants: 0, totals: nil)
        let saved = ChallengeMath.measuredSavings(challenge: challenge, intervals: UsageAnalysis.intervals(from: entries), now: day(40))
        #expect(saved != nil)
        #expect(abs((saved ?? 0) - 300) < 15)
    }

    @Test("Demo data shows a possible leak and a goal")
    func demoData() {
        let data = DemoData.conservation()
        let intervals = UsageAnalysis.intervals(from: data.entries)
        #expect(UsageAnalysis.unusualUsage(intervals) != nil)
        #expect(data.goal != nil)
        #expect(UsageAnalysis.comparisons(intervals).count == 3)
    }

    @Test("Older saved profiles without a water source load as private wells")
    func profileMigration() throws {
        let json = #"{"infantOrPregnant":true,"wellAge":"notSure","county":"wright"}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(HouseholdProfile.self, from: json)
        #expect(profile.waterSource == .privateWell)
    }
}

@MainActor
struct LocalWaterTests {
    @Test("Drought text matches the Drought Monitor numbers")
    func droughtText() {
        let summary = DroughtSummary(county: "Wright County", mapDate: .now, d0: 100, d1: 99.15, d2: 24.07, d3: 0, d4: 0)
        #expect(summary.inDrought)
        #expect(summary.worstCategory == "Severe drought")
        let update = LocalWaterContent.drought(summary)
        #expect(update.whatsHappening.contains("99%"))
        #expect(update.needsAttention)
    }

    @Test("No drought is reported calmly")
    func noDrought() {
        let summary = DroughtSummary(county: "Anoka County", mapDate: .now, d0: 0, d1: 0, d2: 0, d3: 0, d4: 0)
        #expect(!summary.inDrought)
        #expect(!LocalWaterContent.drought(summary).needsAttention)
    }

    @Test("Every MN-06 county has a federal code; Other has none")
    func countyCodes() {
        for county in County.allCases where county != .other {
            #expect(county.fips?.count == 5)
            #expect(county.seatCoordinate != nil)
        }
        #expect(County.other.fips == nil)
    }

    @Test("Every action explains why it matters and links an official source")
    func actionCenter() {
        for action in ActionCenter.actions {
            #expect(!action.whyItMatters.isEmpty)
            #expect(!action.steps.isEmpty)
            #expect(!action.sources.isEmpty)
        }
    }
}
