import Foundation
import Observation

/// App settings that are not part of the household profile.
struct AppSettings: Codable, Equatable {
    /// The ClearWell server that talks to Claude. The API key lives there, never in the app.
    var serverURL: String = AppSettings.defaultServerURL
    /// Optional shared secret the server checks, so strangers can't use your API credits.
    var appToken: String = ""
    var remindersOn: Bool = false

    #if targetEnvironment(simulator)
    static let defaultServerURL = "http://localhost:8787"
    #else
    static let defaultServerURL = ""
    #endif
}

/// Everything ClearWell saves. Stored as one JSON file on this phone only.
@Observable
final class WaterStore {
    private(set) var tests: [WaterTest] = []
    var profile: HouseholdProfile? { didSet { save() } }
    var settings = AppSettings() { didSet { save() } }
    /// Meter readings, bills, habits and goal for the Conserve tab.
    var conservation = ConservationData() { didSet { save() } }
    /// Community challenges this household joined, by challenge ID.
    var challengeParticipation: [String: ChallengeParticipation] = [:] { didSet { save() } }

    private let fileURL: URL
    private var isLoading = false

    private struct SavedData: Codable {
        var tests: [WaterTest]
        var profile: HouseholdProfile?
        var settings: AppSettings?
        // Added later; optional so older saved files still load.
        var conservation: ConservationData?
        var challengeParticipation: [String: ChallengeParticipation]?
    }

    init(fileURL: URL = WaterStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultFileURL: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "clearwell.json")
    }

    // MARK: - Reading

    /// Newest test first.
    var latestTest: WaterTest? { tests.first }

    func test(id: WaterTest.ID) -> WaterTest? {
        tests.first { $0.id == id }
    }

    /// The household profile, or defaults if onboarding hasn't finished yet.
    var currentProfile: HouseholdProfile { profile ?? HouseholdProfile() }

    /// Periods of water use worked out from readings and bills, oldest first.
    var usageIntervals: [UsageInterval] { UsageAnalysis.intervals(from: conservation.entries) }

    // MARK: - Changing

    func add(_ test: WaterTest) {
        tests.append(test)
        sortAndSave()
    }

    func update(_ test: WaterTest) {
        guard let index = tests.firstIndex(where: { $0.id == test.id }) else { return }
        tests[index] = test
        sortAndSave()
    }

    func delete(_ test: WaterTest) {
        tests.removeAll { $0.id == test.id }
        save()
    }

    func saveExplanations(_ explanations: [Contaminant: Explanation], for testID: WaterTest.ID, profile: HouseholdProfile) {
        guard let index = tests.firstIndex(where: { $0.id == testID }) else { return }
        tests[index].explanations = explanations
        tests[index].explainedFor = profile
        save()
    }

    // MARK: - Water use

    func addUsage(_ entry: UsageEntry) {
        conservation.entries.append(entry)
        conservation.entries.sort { $0.date < $1.date }
    }

    func deleteUsage(_ entry: UsageEntry) {
        conservation.entries.removeAll { $0.id == entry.id }
    }

    /// Replaces all tests and water use with the demo set (hidden option for the demo video).
    func loadDemoData() {
        tests = DemoData.tests()
        conservation = DemoData.conservation()
        if profile == nil { profile = DemoData.profile }
        sortAndSave()
    }

    func eraseAll() {
        tests = []
        profile = nil
        settings = AppSettings()
        conservation = ConservationData()
        challengeParticipation = [:]
        save()
    }

    // MARK: - Saving

    private func sortAndSave() {
        tests.sort { $0.date > $1.date }
        save()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else { return }
        tests = saved.tests.sorted { $0.date > $1.date }
        profile = saved.profile
        settings = saved.settings ?? AppSettings()
        conservation = saved.conservation ?? ConservationData()
        challengeParticipation = saved.challengeParticipation ?? [:]
    }

    private func save() {
        guard !isLoading else { return }
        let saved = SavedData(tests: tests, profile: profile, settings: settings,
                              conservation: conservation, challengeParticipation: challengeParticipation)
        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("ClearWell: could not save data: \(error)")
        }
    }
}
