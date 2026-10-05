import Foundation
import Testing
@testable import Clear_Well

@MainActor
struct OfficialLimitsTests {
    @Test("Every contaminant has a row in the limits table")
    func everyContaminantHasALimit() {
        for contaminant in Contaminant.allCases {
            #expect(OfficialLimits.limit(for: contaminant).contaminant == contaminant)
            #expect(!contaminant.limit.sources.isEmpty, "\(contaminant) needs at least one source")
        }
    }

    @Test("Nitrate: green below 3, amber from 3, red from the EPA limit of 10 mg/L")
    func nitrate() {
        #expect(OfficialLimits.status(for: .nitrate, value: 0) == .green)
        #expect(OfficialLimits.status(for: .nitrate, value: 2.9) == .green)
        #expect(OfficialLimits.status(for: .nitrate, value: 3) == .amber)
        #expect(OfficialLimits.status(for: .nitrate, value: 9.99) == .amber)
        #expect(OfficialLimits.status(for: .nitrate, value: 10) == .red)
        #expect(OfficialLimits.status(for: .nitrate, value: 14.2) == .red)
    }

    @Test("Arsenic: any detection is amber, red from the EPA limit of 10 µg/L")
    func arsenic() {
        #expect(OfficialLimits.status(for: .arsenic, value: 0) == .green)
        #expect(OfficialLimits.status(for: .arsenic, value: 1) == .amber)
        #expect(OfficialLimits.status(for: .arsenic, value: 10) == .red)
    }

    @Test("Lead: red at the EPA action level of 15 µg/L")
    func lead() {
        #expect(OfficialLimits.status(for: .lead, value: 0) == .green)
        #expect(OfficialLimits.status(for: .lead, value: 5) == .amber)
        #expect(OfficialLimits.status(for: .lead, value: 15) == .red)
    }

    @Test("Manganese uses the stricter MDH infant limit when a baby is at home")
    func manganeseDependsOnHousehold() {
        #expect(OfficialLimits.status(for: .manganese, value: 40) == .green)
        #expect(OfficialLimits.status(for: .manganese, value: 140) == .amber)
        #expect(OfficialLimits.status(for: .manganese, value: 140, infantOrPregnantAtHome: true) == .red)
        #expect(OfficialLimits.status(for: .manganese, value: 300) == .red)
    }

    @Test("Fluoride: amber from 2 mg/L, red from the EPA limit of 4 mg/L")
    func fluoride() {
        #expect(OfficialLimits.status(for: .fluoride, value: 0.7) == .green)
        #expect(OfficialLimits.status(for: .fluoride, value: 2) == .amber)
        #expect(OfficialLimits.status(for: .fluoride, value: 4) == .red)
    }

    @Test("Coliform bacteria: present is red, absent is green")
    func coliform() {
        #expect(OfficialLimits.status(for: .coliform, value: 1) == .red)
        #expect(OfficialLimits.status(for: .coliform, value: 0) == .green)
    }

    @Test("Unreadable numbers ask the user to check instead of showing green")
    func invalidValues() {
        #expect(OfficialLimits.status(for: .nitrate, value: -1) == .amber)
        #expect(OfficialLimits.status(for: .nitrate, value: .nan) == .amber)
    }

    @Test("Results are sorted red first, then amber, then green")
    func sorting() {
        let test = WaterTest(date: .now, county: .wright, readings: [
            Reading(contaminant: .fluoride, value: 0.2),   // green
            Reading(contaminant: .arsenic, value: 3),      // amber
            Reading(contaminant: .nitrate, value: 14.2),   // red
        ])
        let order = test.sortedReadings(profile: HouseholdProfile()).map(\.contaminant)
        #expect(order == [.nitrate, .arsenic, .fluoride])
        #expect(test.overallStatus(profile: HouseholdProfile()) == .red)
    }
}

@MainActor
struct StandardExplainerTests {
    @Test("High nitrate with a baby at home leads with the infant risk")
    func infantFirst() {
        let profile = HouseholdProfile(infantOrPregnant: true, wellAge: .notSure, county: .wright)
        let explanation = StandardExplainer.explain(Reading(contaminant: .nitrate, value: 14.2), profile: profile, trend: nil)
        #expect(explanation.text.hasPrefix("This matters most in your home: babies"))
        #expect(explanation.text.contains("above the official limit of 10 mg/L"))
        #expect(explanation.nextStep.contains("bottled water"))
        #expect(explanation.origin == .standard)
    }

    @Test("Without a baby at home, the explanation starts with the result")
    func noInfant() {
        let explanation = StandardExplainer.explain(Reading(contaminant: .arsenic, value: 3.8), profile: HouseholdProfile(), trend: nil)
        #expect(explanation.text.hasPrefix("Your arsenic is 3.8 µg/L."))
    }

    @Test("First sentence handles a period inside quotes")
    func firstSentence() {
        let text = "It is called \"blue baby syndrome.\" Levels above 3 mg/L matter."
        #expect(text.firstSentence == "It is called \"blue baby syndrome.\"")
    }
}

@MainActor
struct UnitConversionTests {
    @Test("µg/L and mg/L convert into the table's unit")
    func microgramsAndMilligrams() {
        #expect(UnitConversion.normalize(0.012, unit: "mg/L", for: .arsenic) == 12)
        #expect(UnitConversion.normalize(12, unit: "ug/L", for: .arsenic) == 12)
        #expect(UnitConversion.normalize(12, unit: "ppb", for: .arsenic) == 12)
        #expect(UnitConversion.normalize(4.2, unit: "ppm", for: .nitrate) == 4.2)
        #expect(UnitConversion.normalize(4.2, unit: "furlongs", for: .nitrate) == nil)
    }

    @Test("Nitrate reported as the nitrate ion converts to nitrate-nitrogen")
    func nitrateIon() throws {
        let value = try #require(UnitConversion.normalize(44.3, unit: "mg/L", for: .nitrate, nitrateBasis: .asNitrate))
        #expect(abs(value - 10.0) < 0.05)
    }
}

@MainActor
struct ScheduleAndTrendTests {
    private func date(_ year: Int, _ month: Int = 6) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    @Test("Nitrate is due two years after the last nitrate test")
    func nitrateDue() throws {
        let tests = [WaterTest(date: date(2025), county: .wright, readings: [Reading(contaminant: .nitrate, value: 4)])]
        let due = try #require(TestingSchedule.nextDue(for: .nitrate, tests: tests, now: date(2026)))
        #expect(Calendar.current.component(.year, from: due.date) == 2027)
        #expect(!due.neverTested)
    }

    @Test("Arsenic needs testing once; after that nothing is due")
    func arsenicOnce() {
        #expect(TestingSchedule.nextDue(for: .arsenic, tests: [], now: date(2026))?.neverTested == true)
        let tests = [WaterTest(date: date(2020), county: .wright, readings: [Reading(contaminant: .arsenic, value: 0)])]
        #expect(TestingSchedule.nextDue(for: .arsenic, tests: tests, now: date(2026)) == nil)
    }

    @Test("Due dates read as now, tomorrow, days or months")
    func relativeDescriptions() {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date(2026))!
        let earlierToday = calendar.date(byAdding: .hour, value: -3, to: noon)!
        #expect(TestingSchedule.relativeDescription(of: earlierToday, now: noon) == "now")
        #expect(TestingSchedule.relativeDescription(of: noon, now: noon) == "now")
        #expect(TestingSchedule.relativeDescription(of: calendar.date(byAdding: .day, value: 1, to: noon)!, now: noon) == "tomorrow")
        #expect(TestingSchedule.relativeDescription(of: calendar.date(byAdding: .day, value: 12, to: noon)!, now: noon) == "in 12 days")
        #expect(TestingSchedule.relativeDescription(of: calendar.date(byAdding: .month, value: 4, to: noon)!, now: noon) == "in 4 months")
    }

    @Test("With no tests, nitrate comes first and everything is due now")
    func newUserSchedule() {
        let upcoming = TestingSchedule.upcoming(tests: [], now: date(2026))
        #expect(upcoming.first?.contaminant == .nitrate)
        let allNeverTested = upcoming.allSatisfy { $0.neverTested }
        #expect(allNeverTested)
        #expect(upcoming.count == Contaminant.allCases.count)
    }

    @Test("Trend detects four rising nitrate tests")
    func risingTrend() throws {
        let values: [(Int, Double)] = [(2023, 2.1), (2024, 2.4), (2025, 3.1), (2026, 4.0)]
        let tests = values.map { WaterTest(date: date($0.0), county: .wright, readings: [Reading(contaminant: .nitrate, value: $0.1)]) }
        let trend = try #require(TrendAnalysis.trend(for: .nitrate, tests: tests))
        #expect(trend.direction == .rising)
        #expect(trend.consecutiveRises == 3)
        #expect(trend.summary.contains("last 4 tests"))
    }

    @Test("Scanned results must each be confirmed before saving")
    func scanNeedsConfirmation() {
        let scan = AdvisorClient.ScanResult(testDate: "2026-08-14", labName: "Test Lab", readings: [
            .init(contaminant: "nitrate", nameOnReport: "Nitrate-N", value: 14.2, unit: "mg/L", present: nil, nitrateBasis: .asNitrogen, belowDetectionLimit: false),
            .init(contaminant: "coliform", nameOnReport: "Total Coliform", value: nil, unit: nil, present: false, nitrateBasis: nil, belowDetectionLimit: nil),
        ])
        var draft = TestDraft(scan: scan, county: .wright)
        #expect(draft.values[.nitrate] == "14.2")
        #expect(draft.coliform == .absent)
        #expect(draft.problem != nil)
        draft.needsConfirmation.removeAll()
        #expect(draft.problem == nil)
        #expect(draft.makeTest().readings.count == 2)
    }
}
