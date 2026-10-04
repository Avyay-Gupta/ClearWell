import SwiftUI

/// One card per contaminant, worst first, each explained in plain English for this household.
struct ResultsView: View {
    var testID: WaterTest.ID

    @Environment(WaterStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var aiState = AIState.idle

    enum AIState: Equatable {
        case idle, loading, done, unavailable(String)
    }

    var body: some View {
        if let test = store.test(id: testID) {
            content(test)
        } else {
            ContentUnavailableView("Test not found", systemImage: "questionmark.folder", description: Text("This test may have been deleted."))
        }
    }

    private func content(_ test: WaterTest) -> some View {
        let profile = store.currentProfile
        let overall = test.overallStatus(profile: profile) ?? .green
        let historyUpToTest = store.tests.filter { $0.date <= test.date }

        return ScrollView {
            VStack(spacing: 16) {
                summary(test, overall: overall)

                aiBanner

                ForEach(test.sortedReadings(profile: profile), id: \.contaminant) { reading in
                    ContaminantCard(
                        reading: reading,
                        status: test.status(for: reading.contaminant, profile: profile) ?? .green,
                        explanation: explanation(for: reading, in: test, profile: profile, history: historyUpToTest),
                        trend: TrendAnalysis.trend(for: reading.contaminant, tests: historyUpToTest),
                        infantOrPregnant: profile.infantOrPregnant)
                }

                if overall == .red {
                    Button {
                        router.tab = .help
                    } label: {
                        Label("Get help nearby", systemImage: "phone.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.actionBlue)
                    .controlSize(.large)
                }

                TrustNote()
                Text("ClearWell is not a substitute for a certified lab or the Minnesota Department of Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profile) {
            await loadExplanations(for: test, profile: profile)
        }
    }

    // MARK: - Pieces

    private func summary(_ test: WaterTest, overall: WaterStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(test.date.longDate)
                    .font(.headline)
                Spacer()
                StatusBadge(status: overall)
            }
            Text([test.labName, test.county.fullName, "\(test.readings.count) results"].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder
    private var aiBanner: some View {
        switch aiState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Writing plain-English explanations for your household…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label("Showing standard explanations", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    if let test = store.test(id: testID) {
                        Task { await loadExplanations(for: test, profile: store.currentProfile, force: true) }
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        case .idle, .done:
            EmptyView()
        }
    }

    // MARK: - Explanations

    private func explanation(for reading: Reading, in test: WaterTest, profile: HouseholdProfile, history: [WaterTest]) -> Explanation {
        if test.explainedFor == profile, let ai = test.explanations[reading.contaminant] {
            return ai
        }
        return StandardExplainer.explain(reading, profile: profile, trend: TrendAnalysis.trend(for: reading.contaminant, tests: history))
    }

    private func loadExplanations(for test: WaterTest, profile: HouseholdProfile, force: Bool = false) async {
        if !force, test.explainedFor == profile, !test.explanations.isEmpty {
            aiState = .done
            return
        }
        guard !store.settings.serverURL.isEmpty else {
            aiState = .unavailable("Connect the ClearWell AI server in Settings to get explanations written for your household.")
            return
        }
        aiState = .loading
        do {
            let explanations = try await AdvisorClient(settings: store.settings).explain(test, allTests: store.tests, profile: profile)
            guard !explanations.isEmpty else {
                aiState = .unavailable("The AI didn't return any explanations.")
                return
            }
            store.saveExplanations(explanations, for: test.id, profile: profile)
            withAnimation { aiState = .done }
        } catch is CancellationError {
            aiState = .idle
        } catch {
            aiState = .unavailable(error.localizedDescription)
        }
    }
}

/// One contaminant: name, value vs limit, status, explanation, next step, and details.
struct ContaminantCard: View {
    var reading: Reading
    var status: WaterStatus
    var explanation: Explanation
    var trend: Trend?
    var infantOrPregnant: Bool

    @State private var showDetails = false

    private var limit: OfficialLimit { reading.contaminant.limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(limit.name)
                        .font(.title3.bold())
                    Text(limit.plainDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                StatusBadge(status: status, compact: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.formatted)
                    .font(.system(.title, design: .rounded).bold())
                    .monospacedDigit()
                Text(limit.limitLabel.keepingUnitsTogether)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if limit.kind == .amount, let red = limit.redLine(infantOrPregnantAtHome: infantOrPregnant) {
                LimitBar(value: reading.value, amberAt: limit.amberAt, redAt: red, unit: limit.unit)
            }

            Text(explanation.text.keepingUnitsTogether)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                explanation.origin == .ai ? "Explained by AI for your household" : "Standard explanation from official guidance",
                systemImage: explanation.origin == .ai ? "sparkles" : "book.closed")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !explanation.nextStep.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to do next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status == .green ? Color.secondary : status.color)
                    Text(explanation.nextStep.keepingUnitsTogether)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(status.color.opacity(status == .green ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    detail("Most at risk", limit.mostAtRisk)
                    detail("Why it matters", limit.whyItMatters)
                    detail("Testing schedule", limit.retest.description + " (Minnesota Department of Health).")
                    if let trend, trend.points.count >= 2, limit.kind == .amount {
                        detail("Trend", trend.summary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources")
                            .font(.subheadline.weight(.semibold))
                        ForEach(limit.sources, id: \.self) { source in
                            Link(destination: source.url) {
                                Label(source.title, systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Details and sources")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .card(accent: status.color)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text.keepingUnitsTogether)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
