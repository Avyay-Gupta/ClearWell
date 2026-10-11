import Charts
import SwiftUI

/// Screens inside the Water Quality tab.
enum QualityRoute: Hashable {
    case add
    case form(TestDraft)
    case results(WaterTest.ID)
}

/// The Water Quality tab: add a test, and see every saved test with a chart per contaminant
/// (the official limit drawn as a line).
struct WaterQualityView: View {
    @Environment(WaterStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selected: Contaminant = .nitrate
    @State private var range = TimeRange.all
    @State private var testToDelete: WaterTest?

    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "All", fiveYears = "5 years", twoYears = "2 years"
        var id: String { rawValue }

        var startDate: Date? {
            switch self {
            case .all: nil
            case .fiveYears: Calendar.current.date(byAdding: .year, value: -5, to: .now)
            case .twoYears: Calendar.current.date(byAdding: .year, value: -2, to: .now)
            }
        }
    }

    private var testedContaminants: [Contaminant] {
        Contaminant.allCases.filter { c in store.tests.contains { $0.value(for: c) != nil } }
    }

    private var testsInRange: [WaterTest] {
        guard let start = range.startDate else { return store.tests }
        return store.tests.filter { $0.date >= start }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.qualityPath) {
            Group {
                if store.tests.isEmpty {
                    ContentUnavailableView {
                        Label("No tests yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Each test you add appears here, so you can see whether your water is getting better or worse over the years.")
                    } actions: {
                        Button("Add your first test") {
                            router.qualityPath = [.add]
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.actionBlue)
                    }
                } else {
                    list
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Water Quality")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.qualityPath.append(.add)
                    } label: {
                        Label("Add a test", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: QualityRoute.self) { route in
                switch route {
                case .add:
                    AddResultsView()
                case .form(let draft):
                    TestFormView(initialDraft: draft)
                case .results(let id):
                    ResultsView(testID: id)
                }
            }
            .onAppear {
                if !testedContaminants.contains(selected), let first = testedContaminants.first {
                    selected = first
                }
            }
            .confirmationDialog(
                "Delete this test?",
                isPresented: Binding(get: { testToDelete != nil }, set: { if !$0 { testToDelete = nil } }),
                titleVisibility: .visible,
                presenting: testToDelete) { test in
                Button("Delete test from \(test.date.longDate)", role: .destructive) {
                    store.delete(test)
                }
            } message: { _ in
                Text("This removes it from this phone. It can't be undone.")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Button {
                    router.qualityPath.append(.add)
                } label: {
                    Label("Add a water test", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(testedContaminants) { contaminant in
                            Button {
                                withAnimation { selected = contaminant }
                            } label: {
                                Text(contaminant.name)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(selected == contaminant ? Color.white : Color.primary)
                                    .background(selected == contaminant ? Color.actionBlue : Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == contaminant ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                Picker("Time range", selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let trend = TrendAnalysis.trend(for: selected, tests: testsInRange) {
                    if selected.limit.kind == .amount {
                        ContaminantChart(contaminant: selected, trend: trend, profile: store.currentProfile)
                            .frame(height: 260)
                            .padding(.vertical, 8)
                        TrendSummary(contaminant: selected, trend: trend)
                    } else {
                        PresenceTimeline(trend: trend)
                    }
                } else {
                    Text("No \(selected.name.lowercased()) results in this time range.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("All tests") {
                ForEach(store.tests) { test in
                    NavigationLink(value: QualityRoute.results(test.id)) {
                        TestRow(test: test, profile: store.currentProfile)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            testToDelete = test
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ContaminantChart: View {
    var contaminant: Contaminant
    var trend: Trend
    var profile: HouseholdProfile

    private var limit: OfficialLimit { contaminant.limit }
    private var redLine: Double? { limit.redLine(infantOrPregnantAtHome: profile.infantOrPregnant) }
    private var yMax: Double { max((redLine ?? 0) * 1.3, trend.maximum * 1.15, 0.001) }

    var body: some View {
        Chart {
            if let redLine {
                RuleMark(y: .value("Official limit", redLine))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Limit \(redLine.formatted()) \(limit.unit)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
            }

            ForEach(trend.points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(limit.unit, point.value))
                    .foregroundStyle(Color.accentColor)

                let status = OfficialLimits.status(for: contaminant, value: point.value, infantOrPregnantAtHome: profile.infantOrPregnant)
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(limit.unit, point.value))
                    .foregroundStyle(by: .value("Status", status.title))
                    .symbol(by: .value("Status", status.title))
                    .symbolSize(90)
                    .annotation(position: .top) {
                        Text(point.value.formatted())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartForegroundStyleScale([
            WaterStatus.green.title: WaterStatus.green.color,
            WaterStatus.amber.title: WaterStatus.amber.color,
            WaterStatus.red.title: WaterStatus.red.color,
        ])
        .chartSymbolScale([
            WaterStatus.green.title: .circle,
            WaterStatus.amber.title: .triangle,
            WaterStatus.red.title: .square,
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxisLabel(limit.unit)
        .accessibilityLabel("\(contaminant.name) over time")
    }
}

private struct TrendSummary: View {
    var contaminant: Contaminant
    var trend: Trend

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(trend.summary)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
            }
            if trend.points.count >= 2 {
                Text("Lowest \(Reading.format(trend.minimum, for: contaminant)) · Highest \(Reading.format(trend.maximum, for: contaminant)) · \(trend.points.count) tests")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch trend.direction {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .steady: "arrow.right"
        }
    }
}

private struct PresenceTimeline: View {
    var trend: Trend

    var body: some View {
        ForEach(trend.points.reversed()) { point in
            HStack {
                Text(point.date.longDate)
                Spacer()
                StatusBadge(status: point.value >= 1 ? .red : .green, compact: true)
                Text(point.value >= 1 ? "Present" : "Absent")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TestRow: View {
    var test: WaterTest
    var profile: HouseholdProfile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.date.longDate)
                    .font(.body.weight(.medium))
                Text("\(test.readings.count) results" + (test.labName.map { " · \($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status = test.overallStatus(profile: profile) {
                StatusBadge(status: status, compact: true)
            }
        }
    }
}
