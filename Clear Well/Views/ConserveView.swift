import Charts
import SwiftUI

/// Household water conservation: track use, compare periods, set a goal, spot leaks, get ideas.
/// Works for private-well and city-water homes.
struct ConserveView: View {
    @Environment(WaterStore.self) private var store
    @Environment(LocalWaterStore.self) private var localWater

    @State private var addingKind: UsageEntry.Kind?
    @State private var showGoal = false
    @State private var showHabits = false
    @State private var aiState = AIState.idle

    enum AIState: Equatable {
        case idle, loading, unavailable(String)
    }

    private var intervals: [UsageInterval] { store.usageIntervals }
    private var unusual: UnusualUsage? { UsageAnalysis.unusualUsage(intervals) }
    private var season: Season { Season(date: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if intervals.isEmpty {
                        gettingStarted
                    } else {
                        if let unusual { UnusualUsageCard(unusual: unusual) }
                        UsageSummaryCard(intervals: intervals, people: store.conservation.habits.people)
                        UsageChartCard(intervals: intervals, goal: store.conservation.goal, unusual: unusual)
                        GoalCard(goal: store.conservation.goal, intervals: intervals) { showGoal = true }
                    }

                    recommendations

                    if !store.conservation.entries.isEmpty {
                        NavigationLink {
                            UsageEntriesList()
                        } label: {
                            HStack {
                                Label("All readings and bills", systemImage: "list.bullet")
                                Spacer()
                                Text("\(store.conservation.entries.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .card(padding: 16)
                        }
                        .buttonStyle(.plain)
                    }

                    Label("Measured numbers come only from your own meter readings or bills. Savings marked \"Estimate\" use published averages and could be different for your home.", systemImage: "ruler")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Conserve")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add a meter reading", systemImage: "gauge.with.dots.needle.33percent") { addingKind = .meterReading }
                        Button("Add a water bill", systemImage: "doc.text") { addingKind = .bill }
                        Divider()
                        Button("Household habits", systemImage: "house") { showHabits = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $addingKind) { kind in
                UsageEntryForm(kind: kind)
            }
            .sheet(isPresented: $showGoal) {
                GoalSheet(intervals: intervals)
            }
            .sheet(isPresented: $showHabits) {
                NavigationStack { HabitsForm() }
            }
            .task(id: recommendationKey) {
                await loadAIRecommendations()
            }
        }
    }

    // MARK: - Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Track your water use")
                .font(.title2.bold())
            Text(store.currentProfile.hasPrivateWell
                 ? "If your well has a water meter, add a reading now and another in a few days. ClearWell will work out how much you use, compare weeks and months, and flag anything that looks like a leak."
                 : "Add the usage from your last few water bills, or read your water meter. ClearWell will compare your use over time and flag anything that looks like a leak.")
                .foregroundStyle(.secondary)
            HStack {
                Button { addingKind = .meterReading } label: {
                    Label("Meter reading", systemImage: "gauge.with.dots.needle.33percent")
                        .frame(maxWidth: .infinity)
                }
                Button { addingKind = .bill } label: {
                    Label("Water bill", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .card()
    }

    // MARK: - Recommendations

    private var currentRecommendations: [Recommendation] {
        let data = store.conservation
        if data.aiRecommendationsKey == recommendationKey, !data.aiRecommendations.isEmpty {
            return data.aiRecommendations
        }
        return StandardRecommendations.make(habits: data.habits, unusual: unusual, season: season, inDrought: localWater.drought?.inDrought ?? false)
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Ideas for your household")
                Button("Habits") { showHabits = true }
                    .font(.subheadline)
            }
            switch aiState {
            case .loading:
                Label("Writing suggestions for your household…", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            case .unavailable(let reason):
                Text("Showing standard tips. \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            case .idle:
                EmptyView()
            }
            ForEach(currentRecommendations) { RecommendationCard(recommendation: $0) }
        }
    }

    /// Changes when anything the suggestions depend on changes.
    private var recommendationKey: String {
        let habits = store.conservation.habits
        let latest = intervals.last.map { Int($0.gallonsPerDay / 10) * 10 } ?? 0
        return [season.rawValue, "\(habits.people)", habits.outdoorWatering.rawValue, habits.olderToilets.rawValue,
                habits.olderShowerheads.rawValue, "\(latest)", "\(unusual != nil)",
                "\(store.conservation.goal?.reductionPercent ?? 0)", "\(localWater.drought?.inDrought ?? false)",
                store.currentProfile.waterSource.rawValue].joined(separator: "|")
    }

    private func loadAIRecommendations() async {
        let key = recommendationKey
        if store.conservation.aiRecommendationsKey == key, !store.conservation.aiRecommendations.isEmpty {
            aiState = .idle
            return
        }
        guard !store.settings.serverURL.isEmpty else {
            aiState = .unavailable("Connect the ClearWell AI server in Settings for suggestions written for your household.")
            return
        }
        aiState = .loading
        let habits = store.conservation.habits
        let profile = store.currentProfile
        let request = AdvisorClient.ConserveRequest(
            season: season.rawValue,
            county: profile.county.fullName,
            waterSource: profile.waterSource.label,
            people: habits.people,
            outdoorWatering: habits.outdoorWatering.label,
            olderToilets: habits.olderToilets.label,
            olderShowerheads: habits.olderShowerheads.label,
            latestGallonsPerDay: intervals.last.map { Int($0.gallonsPerDay.rounded()) },
            typicalGallonsPerDay: UsageAnalysis.baselineGallonsPerDay(intervals).map { Int($0.rounded()) },
            comparisons: UsageAnalysis.comparisons(intervals).map {
                .init(period: $0.label, currentGallonsPerDay: Int($0.current.rounded()),
                      previousGallonsPerDay: Int($0.previous.rounded()), percentChange: Int($0.percentChange.rounded()))
            },
            possibleLeak: unusual != nil,
            goalPercent: store.conservation.goal?.reductionPercent,
            countyInDrought: localWater.drought?.inDrought ?? false)
        do {
            let list = try await AdvisorClient(settings: store.settings).conserve(request)
            guard !list.isEmpty else {
                aiState = .unavailable("The AI didn't return any suggestions.")
                return
            }
            store.conservation.aiRecommendations = list
            store.conservation.aiRecommendationsKey = key
            aiState = .idle
        } catch is CancellationError {
            aiState = .idle
        } catch {
            aiState = .unavailable(error.localizedDescription)
        }
    }
}

extension UsageEntry.Kind: Identifiable {
    var id: String { rawValue }
}

extension Double {
    /// "1,234" — whole gallons with a thousands separator.
    var gallonsText: String { formatted(.number.precision(.fractionLength(0))) }
}

// MARK: - Cards

/// Clear tag so measured numbers and estimates are never confused.
struct DataKindTag: View {
    var isEstimate: Bool

    var body: some View {
        Text(isEstimate ? "Estimate" : "Measured")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(isEstimate ? Color.purple : Color.teal)
            .background((isEstimate ? Color.purple : Color.teal).opacity(0.14), in: Capsule())
            .accessibilityLabel(isEstimate ? "Estimate" : "Measured")
    }
}

private struct UnusualUsageCard: View {
    var unusual: UnusualUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unusual use — possible leak", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("From \(unusual.interval.start.formatted(date: .abbreviated, time: .omitted)) to \(unusual.interval.end.formatted(date: .abbreviated, time: .omitted)) you used about \(unusual.interval.gallonsPerDay.gallonsText) gallons a day — \(Int(unusual.percentAbove.rounded()))% more than your usual \(unusual.baselineGallonsPerDay.gallonsText).")
            Text("This can be a leak, like a running toilet, or a change such as guests, laundry day or lawn watering.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick leak check")
                    .font(.subheadline.weight(.semibold))
                Text("Turn off every faucet and water-using appliance, note your meter, and check it again in an hour. If it moved, something is leaking.")
                    .font(.subheadline)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .card(accent: .orange)
    }
}

private struct UsageSummaryCard: View {
    var intervals: [UsageInterval]
    var people: Int

    var body: some View {
        let comparisons = UsageAnalysis.comparisons(intervals)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your water use")
                    .font(.headline)
                Spacer()
                DataKindTag(isEstimate: false)
            }
            if let latest = intervals.last {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(latest.gallonsPerDay.gallonsText) gallons a day")
                        .font(.system(.title, design: .rounded).bold())
                    Text("Most recent period: \(latest.start.formatted(date: .abbreviated, time: .omitted)) – \(latest.end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if comparisons.isEmpty {
                Text("Add more readings to compare days, weeks and months. Weekly comparisons need about two weeks of readings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(comparisons) { comparison in
                        HStack {
                            Text("Last \(comparison.label.lowercased()) vs. the one before")
                                .font(.subheadline)
                            Spacer()
                            ChangeLabel(percent: comparison.percentChange)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                DataKindTag(isEstimate: true)
                Text("A typical U.S. home uses about \(Int(WaterSenseFacts.gallonsPerPersonPerDay)) gallons per person a day indoors and out — about \((WaterSenseFacts.gallonsPerPersonPerDay * Double(max(people, 1))).gallonsText) for \(people) \(people == 1 ? "person" : "people") (EPA WaterSense).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// "↓ 9%" in green, "↑ 12%" in orange.
struct ChangeLabel: View {
    var percent: Double

    var body: some View {
        let rounded = Int(percent.rounded())
        let down = rounded < 0
        Label("\(abs(rounded))% \(rounded == 0 ? "same" : (down ? "less" : "more"))",
              systemImage: rounded == 0 ? "equal" : (down ? "arrow.down.right" : "arrow.up.right"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(rounded == 0 ? Color.secondary : (down ? Color.green : Color.orange))
    }
}

private struct UsageChartCard: View {
    var intervals: [UsageInterval]
    var goal: ConservationGoal?
    var unusual: UnusualUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gallons per day")
                .font(.headline)
            Chart {
                ForEach(intervals.suffix(20)) { interval in
                    BarMark(
                        xStart: .value("Start", interval.start),
                        xEnd: .value("End", interval.end),
                        y: .value("Gallons per day", interval.gallonsPerDay))
                        .foregroundStyle(unusual?.interval == interval ? Color.orange : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if let goal {
                    RuleMark(y: .value("Goal", goal.targetGallonsPerDay))
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Goal \(goal.targetGallonsPerDay.gallonsText)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Gallons per day for each reading period")
        }
        .card()
    }
}

private struct GoalCard: View {
    var goal: ConservationGoal?
    var intervals: [UsageInterval]
    var edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Conservation goal", systemImage: "target")
                    .font(.headline)
                Spacer()
                Button(goal == nil ? "Set a goal" : "Change", action: edit)
                    .font(.subheadline.weight(.semibold))
            }
            if let goal {
                Text("Use \(goal.reductionPercent)% less: \(goal.targetGallonsPerDay.gallonsText) gallons a day or fewer (down from \(goal.baselineGallonsPerDay.gallonsText)).")
                if let progress = UsageAnalysis.progress(of: goal, intervals: intervals) {
                    let fraction = min(max((goal.baselineGallonsPerDay - progress.currentGallonsPerDay) / max(goal.baselineGallonsPerDay - goal.targetGallonsPerDay, 1), 0), 1)
                    ProgressView(value: fraction)
                        .tint(progress.onTrack ? .green : .orange)
                    HStack(alignment: .top) {
                        DataKindTag(isEstimate: false)
                        Text(progress.onTrack
                             ? "On track: \(progress.currentGallonsPerDay.gallonsText) gallons a day since you set the goal. You've saved about \(progress.measuredGallonsSaved.gallonsText) gallons so far."
                             : "Not there yet: \(progress.currentGallonsPerDay.gallonsText) gallons a day since you set the goal. Saved so far: \(progress.measuredGallonsSaved.gallonsText) gallons.")
                            .font(.subheadline)
                    }
                } else {
                    Text("Add readings over the next week to see your progress.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Pick a target like \"use 10% less\" and ClearWell will track your progress from your own readings.")
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct RecommendationCard: View {
    var recommendation: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.title)
                .font(.headline)
            Text(recommendation.detail)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let gallons = recommendation.estimatedGallonsPerYear {
                HStack(alignment: .firstTextBaseline) {
                    DataKindTag(isEstimate: true)
                    Text("About \(gallons.gallonsText) gallons a year")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let basis = recommendation.estimateBasis {
                Text(basis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(recommendation.origin == .ai ? "Suggested by AI for your household" : "Standard tip",
                  systemImage: recommendation.origin == .ai ? "sparkles" : "book.closed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card(padding: 16)
    }
}

// MARK: - Entry, goal and habits

struct UsageEntryForm: View {
    var kind: UsageEntry.Kind

    @Environment(WaterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var amountText = ""
    @State private var unit = UsageUnit.gallons

    private var amount: Double? { TestDraft.parse(amountText) }

    private var lastReading: UsageEntry? {
        store.conservation.entries.filter { $0.kind == .meterReading && $0.date < date }.max { $0.date < $1.date }
    }

    private var problem: String? {
        guard let amount else { return "Enter a number." }
        if kind == .bill, date <= startDate { return "The bill's end date must be after its start date." }
        if kind == .meterReading, let lastReading, amount * unit.gallonsPerUnit < lastReading.gallons {
            return "This is lower than your earlier reading. If your meter was replaced, that's OK — the gap will be skipped."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .meterReading {
                    Section {
                        DatePicker("Read on", selection: $date, in: ...Date.now)
                    } footer: {
                        Text("Read your water meter at about the same time each day or week for the best comparisons.")
                    }
                } else {
                    Section("Billing period") {
                        DatePicker("From", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                        DatePicker("To", selection: $date, in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section {
                    HStack {
                        Text(kind == .meterReading ? "Meter reading" : "Water used")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(UsageUnit.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    if let problem {
                        Text(problem)
                    } else {
                        Text(kind == .meterReading
                             ? "Type the whole number shown on the meter. ClearWell subtracts readings to find how much you used."
                             : "Use the usage amount printed on the bill, not the cost.")
                    }
                }
            }
            .navigationTitle(kind == .meterReading ? "Meter reading" : "Water bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount == nil || (kind == .bill && date <= startDate))
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        store.addUsage(UsageEntry(
            kind: kind,
            date: date,
            startDate: kind == .bill ? startDate : nil,
            amount: amount,
            unit: unit))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

struct GoalSheet: View {
    var intervals: [UsageInterval]

    @Environment(WaterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var percent = 10

    private var baseline: Double? { UsageAnalysis.goalBaseline(intervals) }

    var body: some View {
        NavigationStack {
            Form {
                if let baseline {
                    Section {
                        Picker("Use less by", selection: $percent) {
                            ForEach([5, 10, 15, 20, 25], id: \.self) { Text("\($0)%").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        LabeledContent("Your usual use", value: "\(baseline.gallonsText) gal/day")
                        LabeledContent("New target", value: "\((baseline * (1 - Double(percent) / 100)).gallonsText) gal/day")
                    } footer: {
                        Text("Your usual use is measured from your own readings. Progress is tracked from new readings after today.")
                    }
                    Section {
                        Button("Save goal") {
                            store.conservation.goal = ConservationGoal(reductionPercent: percent, baselineGallonsPerDay: baseline, startDate: .now)
                            dismiss()
                        }
                        if store.conservation.goal != nil {
                            Button("Remove goal", role: .destructive) {
                                store.conservation.goal = nil
                                dismiss()
                            }
                        }
                    }
                } else {
                    Text("Add at least two meter readings or one water bill first, so ClearWell knows your usual use.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Conservation goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if let goal = store.conservation.goal { percent = goal.reductionPercent }
            }
        }
    }
}

struct HabitsForm: View {
    @Environment(WaterStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Stepper("People at home: \(store.conservation.habits.people)", value: $store.conservation.habits.people, in: 1...12)
                Picker("Outdoor watering", selection: $store.conservation.habits.outdoorWatering) {
                    ForEach(OutdoorWatering.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Picker("Older toilets (before 1994)", selection: $store.conservation.habits.olderToilets) {
                    ForEach(YesNoUnsure.allCases) { Text($0.label).tag($0) }
                }
                Picker("Older showerheads", selection: $store.conservation.habits.olderShowerheads) {
                    ForEach(YesNoUnsure.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("These answers stay on this phone. They're used to choose conservation ideas, and only a summary is sent to the AI.")
            }
        }
        .navigationTitle("Household habits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UsageEntriesList: View {
    @Environment(WaterStore.self) private var store

    var body: some View {
        List {
            ForEach(store.conservation.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.kind == .meterReading ? "Meter reading" : "Water bill")
                        .font(.body.weight(.medium))
                    Text(description(of: entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.deleteUsage(entry)
                    }
                }
            }
        }
        .navigationTitle("Readings and bills")
        .overlay {
            if store.conservation.entries.isEmpty {
                ContentUnavailableView("No readings yet", systemImage: "gauge.with.dots.needle.33percent")
            }
        }
    }

    private func description(of entry: UsageEntry) -> String {
        let amount = "\(entry.amount.formatted()) \(entry.unit.short)"
        if entry.kind == .bill, let start = entry.startDate {
            return "\(amount) used, \(start.formatted(date: .abbreviated, time: .omitted)) – \(entry.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(amount) on \(entry.date.formatted(date: .abbreviated, time: .shortened))"
    }
}
