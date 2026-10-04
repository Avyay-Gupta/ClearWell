import Foundation

#if DEBUG
/// Developer shortcut: open the app straight to one screen, for screenshots and demo recording.
/// In Xcode: Product → Scheme → Edit Scheme → Run → Arguments, add `-ClearWellScreen results`.
/// Screens: add, form, scan-review, results, history, help. Only exists in Debug builds.
enum LaunchOptions {
    static func apply(to router: AppRouter, store: WaterStore) {
        guard let screen = UserDefaults.standard.string(forKey: "ClearWellScreen") else { return }
        let county = store.currentProfile.county

        switch screen {
        case "add":
            router.tab = .add
        case "form":
            router.tab = .add
            router.addPath = [.form(TestDraft(county: county))]
        case "scan-review":
            router.tab = .add
            router.addPath = [.form(TestDraft(scan: sampleScan, county: county))]
        case "results":
            if let latest = store.latestTest {
                router.tab = .add
                router.addPath = [.results(latest.id)]
            }
        case "history":
            router.tab = .history
        case "help":
            router.tab = .help
        default:
            break
        }
    }

    /// What the AI would return for the sample lab report in docs/sample-lab-report.html.
    static let sampleScan = AdvisorClient.ScanResult(
        testDate: "2026-09-02",
        labName: "North Star Water Testing",
        readings: [
            .init(contaminant: "nitrate", nameOnReport: "Nitrate + Nitrite as N", value: 14.2, unit: "mg/L", present: nil, nitrateBasis: .asNitrogen, belowDetectionLimit: false),
            .init(contaminant: "arsenic", nameOnReport: "Arsenic", value: 3.8, unit: "µg/L", present: nil, nitrateBasis: .unknown, belowDetectionLimit: false),
            .init(contaminant: "lead", nameOnReport: "Lead", value: nil, unit: "µg/L", present: nil, nitrateBasis: .unknown, belowDetectionLimit: true),
            .init(contaminant: "manganese", nameOnReport: "Manganese", value: 0.14, unit: "mg/L", present: nil, nitrateBasis: .unknown, belowDetectionLimit: false),
            .init(contaminant: "fluoride", nameOnReport: "Fluoride", value: 0.4, unit: "mg/L", present: nil, nitrateBasis: .unknown, belowDetectionLimit: false),
            .init(contaminant: "coliform", nameOnReport: "Total Coliform Bacteria", value: nil, unit: nil, present: false, nitrateBasis: .unknown, belowDetectionLimit: false),
        ])
}
#endif
