import Foundation

enum ColiformChoice: String, CaseIterable, Identifiable, Hashable {
    case notTested, absent, present

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notTested: "Not tested"
        case .absent: "Absent (none found)"
        case .present: "Present (found)"
        }
    }
}

/// What the Add Results form is editing, before it becomes a saved `WaterTest`.
struct TestDraft: Hashable {
    var date = Date()
    var county: County = .wright
    var labName = ""
    /// Text typed (or scanned) for each amount, in the unit from the limits table.
    var values: [Contaminant: String] = [:]
    var coliform: ColiformChoice = .notTested
    /// Scanned values the user still has to check against the paper report.
    var needsConfirmation: Set<Contaminant> = []
    /// Notes from the scan, e.g. "Arsenic was below the lab's detection limit."
    var scanNotes: [String] = []
    var entry: WaterTest.Entry = .typed

    static let amountContaminants = Contaminant.allCases.filter { $0.limit.kind == .amount }

    /// Parses "14.2" or "14,2". Returns nil for blank text.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    func isInvalid(_ contaminant: Contaminant) -> Bool {
        let text = values[contaminant, default: ""].trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && TestDraft.parse(text) == nil
    }

    var readings: [Reading] {
        var list = TestDraft.amountContaminants.compactMap { contaminant in
            TestDraft.parse(values[contaminant, default: ""]).map { Reading(contaminant: contaminant, value: $0) }
        }
        switch coliform {
        case .notTested: break
        case .absent: list.append(Reading(contaminant: .coliform, value: 0))
        case .present: list.append(Reading(contaminant: .coliform, value: 1))
        }
        return list
    }

    /// Why Save is disabled, or nil if the test can be saved.
    var problem: String? {
        if TestDraft.amountContaminants.contains(where: isInvalid) { return "Fix the highlighted numbers." }
        if readings.isEmpty { return "Enter at least one result." }
        if !needsConfirmation.isEmpty { return "Confirm each scanned number against your report." }
        return nil
    }

    func makeTest() -> WaterTest {
        WaterTest(
            date: date,
            county: county,
            labName: labName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : labName,
            readings: readings,
            entry: entry)
    }
}

extension TestDraft {
    /// Turns what the AI read from a photo into a draft the user must confirm.
    /// Unit conversion happens here, in code — not in the AI.
    init(scan: AdvisorClient.ScanResult, county: County) {
        self.init()
        self.county = county
        self.entry = .scanned
        if let labName = scan.labName { self.labName = labName }
        if let dateText = scan.testDate, let date = Self.parseDate(dateText) { self.date = date }

        for item in scan.readings {
            guard let contaminant = Contaminant(rawValue: item.contaminant) else { continue }

            if contaminant == .coliform {
                if let present = item.present {
                    coliform = present ? .present : .absent
                    needsConfirmation.insert(.coliform)
                }
                continue
            }

            if item.belowDetectionLimit == true {
                values[contaminant] = "0"
                needsConfirmation.insert(contaminant)
                scanNotes.append("\(contaminant.name) was below the lab's detection limit, so it's entered as 0.")
                continue
            }

            guard let value = item.value else { continue }
            if let unit = item.unit,
               let converted = UnitConversion.normalize(value, unit: unit, for: contaminant, nitrateBasis: item.nitrateBasis ?? .unknown) {
                values[contaminant] = converted.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
                if contaminant == .nitrate, item.nitrateBasis == .asNitrate {
                    scanNotes.append("Nitrate was reported as the nitrate ion (NO₃) and converted to nitrate-nitrogen, which the EPA limit uses.")
                } else if converted != value {
                    scanNotes.append("\(contaminant.name) was reported as \(value.formatted()) \(unit) and converted to \(contaminant.limit.unit).")
                }
            } else {
                values[contaminant] = value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
                scanNotes.append("Check the unit for \(contaminant.name): the report said \"\(item.unit ?? "no unit")\". ClearWell expects \(contaminant.limit.unit).")
            }
            needsConfirmation.insert(contaminant)
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: text), date <= .now else { return nil }
        return date
    }
}
