import SwiftUI

/// Answers two questions at a glance: How is my water doing? What should I do next?
struct HomeView: View {
    @Environment(WaterStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let latest = store.latestTest {
                        NavigationLink(value: latest.id) {
                            StatusCard(test: latest, profile: store.currentProfile)
                        }
                        .buttonStyle(.plain)
                    } else {
                        welcomeCard
                    }

                    NextTestCard(upcoming: TestingSchedule.upcoming(tests: store.tests), hasTests: !store.tests.isEmpty)

                    Button {
                        router.addPath = []
                        router.tab = .add
                    } label: {
                        Label("Add new test results", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.actionBlue)
                    .controlSize(.large)

                    if let latest = store.latestTest {
                        latestResults(latest)
                    }

                    TrustNote()
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("ClearWell")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .navigationDestination(for: WaterTest.ID.self) { id in
                ResultsView(testID: id)
            }
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "drop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Welcome to ClearWell")
                .font(.title2.bold())
            Text("Add your first well water test. ClearWell will tell you what's safe, what isn't, and exactly what to do next.")
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func latestResults(_ test: WaterTest) -> some View {
        VStack(spacing: 10) {
            SectionTitle(text: "Latest results")
            VStack(spacing: 0) {
                let readings = test.sortedReadings(profile: store.currentProfile)
                ForEach(Array(readings.enumerated()), id: \.element.contaminant) { index, reading in
                    NavigationLink(value: test.id) {
                        HStack {
                            Text(reading.contaminant.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(reading.formatted)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            if let status = test.status(for: reading.contaminant, profile: store.currentProfile) {
                                Image(systemName: status.symbol)
                                    .foregroundStyle(status.color)
                                    .accessibilityLabel(status.title)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < readings.count - 1 {
                        Divider()
                    }
                }
            }
            .card(padding: 16)
        }
    }
}

/// The big "Your well: Act now" card.
struct StatusCard: View {
    var test: WaterTest
    var profile: HouseholdProfile

    private var status: WaterStatus { test.overallStatus(profile: profile) ?? .green }

    private var countText: String {
        let red = test.readings.filter { test.status(for: $0.contaminant, profile: profile) == .red }.count
        let amber = test.readings.filter { test.status(for: $0.contaminant, profile: profile) == .amber }.count
        if red > 0 { return red == 1 ? "1 result needs action now" : "\(red) results need action now" }
        if amber > 0 { return amber == 1 ? "1 result to keep an eye on" : "\(amber) results to keep an eye on" }
        return "All \(test.readings.count) results are within official limits"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: status.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your well")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(status.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
            }

            Text(countText)
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                Text("Last test: \(test.date.longDate)")
                Spacer()
                Text("See results")
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [status.color, status.color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: status.color.opacity(0.3), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your latest results")
    }
}

/// "Next test due: nitrate in 4 months".
struct NextTestCard: View {
    var upcoming: [TestingSchedule.Due]
    var hasTests: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next test due", systemImage: "calendar.badge.clock")
                .font(.headline)

            if let next = upcoming.first {
                let others = upcoming.dropFirst()
                let untested = others.filter(\.neverTested).map { $0.contaminant.name.lowercased() }
                let scheduled = others.filter { !$0.neverTested }.prefix(2)
                    .map { "\($0.contaminant.name.lowercased()) \(TestingSchedule.relativeDescription(of: $0.date))" }

                Text(headline(for: next))
                    .font(.title3.weight(.semibold))
                if !untested.isEmpty {
                    Text("Also not tested yet: " + untested.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !scheduled.isEmpty {
                    Text("Coming up: " + scheduled.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("You're up to date.")
                    .font(.title3.weight(.semibold))
            }

            if !hasTests {
                Text("MDH recommends testing for coliform bacteria every year, nitrate every other year, and arsenic and lead at least once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func headline(for due: TestingSchedule.Due) -> String {
        let name = due.contaminant.name
        if due.neverTested { return "\(name) — not tested yet" }
        let when = TestingSchedule.relativeDescription(of: due.date)
        return when == "now" ? "\(name) — due now" : "\(name) \(when)"
    }
}
