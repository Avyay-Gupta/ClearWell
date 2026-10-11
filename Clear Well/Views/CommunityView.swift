import SwiftUI

/// Community water stewardship: local conditions, shared challenges, and ways to help.
struct CommunityView: View {
    @Environment(WaterStore.self) private var store
    @Environment(LocalWaterStore.self) private var localWater
    @State private var challenges: ChallengeList?
    @State private var challengeError: String?

    private var county: County { store.currentProfile.county }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Your water is connected to your neighbors' — the same groundwater, lakes and streams. Here's what's happening locally and how you can help.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    localWaterSection
                    challengesSection
                    actionCenterSection
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Community")
            .refreshable {
                await localWater.refresh(county: county)
                await loadChallenges()
            }
            .task(id: county) {
                await localWater.refreshIfNeeded(county: county)
            }
            .task {
                await loadChallenges()
            }
        }
    }

    // MARK: - Local water dashboard

    private var localWaterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: county == .other ? "Local water" : "Local water · \(county.fullName)")
            switch localWater.state {
            case .loading where localWater.liveUpdates.isEmpty:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking drought, flood alerts and rain…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await localWater.refresh(county: county) } }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 4)
            default:
                EmptyView()
            }
            if county == .other {
                Text("Choose your county in Settings to see live drought, flood and rain updates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(localWater.liveUpdates) { LocalUpdateCard(update: $0, expanded: true) }
            ForEach(LocalWaterContent.reference(county: county)) { LocalUpdateCard(update: $0, expanded: false) }
        }
    }

    // MARK: - Challenges

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Community challenges")
            if let list = challenges {
                ForEach(list.challenges) { challenge in
                    NavigationLink {
                        ChallengeDetailView(challenge: challenge, minimumParticipants: list.minimumParticipants) { updated in
                            challenges = updated
                        }
                    } label: {
                        ChallengeRow(challenge: challenge, joined: store.challengeParticipation[challenge.id] != nil)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional community-wide goals, like using less water this month. Joining shares only anonymous totals.")
                        .font(.subheadline)
                    Text(challengeError ?? "Loading challenges…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card(padding: 16)
            }
        }
    }

    private func loadChallenges() async {
        guard !store.settings.serverURL.isEmpty else {
            challengeError = "Challenges need the ClearWell server. Connect it in Settings → AI server."
            return
        }
        do {
            challenges = try await AdvisorClient(settings: store.settings).challenges()
            challengeError = nil
        } catch is CancellationError {
        } catch {
            challengeError = error.localizedDescription
        }
    }

    // MARK: - Action Center

    private var actionCenterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Action Center")
            VStack(spacing: 0) {
                ForEach(Array(ActionCenter.actions.enumerated()), id: \.element.id) { index, action in
                    NavigationLink {
                        ActionDetailView(action: action)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: action.icon)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(action.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < ActionCenter.actions.count - 1 { Divider() }
                }
            }
            .card(padding: 16)
        }
    }
}

// MARK: - Local update card

struct LocalUpdateCard: View {
    var update: LocalUpdate
    var expanded: Bool
    @State private var showMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: update.topic.icon)
                    .font(.title3)
                    .foregroundStyle(update.needsAttention ? Color.orange : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.title)
                        .font(.headline)
                    if let status = update.status {
                        Text(status)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(update.needsAttention ? Color.orange : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
                if update.isLive {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.teal)
                }
            }

            Text(update.whatsHappening)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if expanded || showMore {
                detail("Why it matters", update.whyItMatters)
                detail("What you can do", update.whatYouCanDo)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(update.sources, id: \.self) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(.footnote)
                        }
                    }
                    if let asOf = update.asOf, update.topic == .drought {
                        Text("Drought map of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Why it matters and what you can do") {
                    withAnimation { showMore = true }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .card(padding: 16, accent: update.needsAttention ? .orange : nil)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Challenges

private struct ChallengeRow: View {
    var challenge: Challenge
    var joined: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if joined {
                    Label("Joined", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            Text(challenge.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Text("\(challenge.participants) \(challenge.participants == 1 ? "household" : "households") taking part")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card(padding: 16)
    }
}

struct ChallengeDetailView: View {
    var challenge: Challenge
    var minimumParticipants: Int
    var onUpdate: (ChallengeList) -> Void

    @Environment(WaterStore.self) private var store
    @State private var current: Challenge?
    @State private var isSending = false
    @State private var sendError: String?

    private var shown: Challenge { current ?? challenge }
    private var participation: ChallengeParticipation? { store.challengeParticipation[challenge.id] }
    private var measured: Double? { ChallengeMath.measuredSavings(challenge: shown, intervals: store.usageIntervals) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(shown.title)
                        .font(.title2.bold())
                    if let start = shown.start, let end = shown.end {
                        Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(shown.summary)
                    Text("Why it matters")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    Text(shown.whyItMatters)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .card()

                communityProgress
                yourParticipation

                Label("Joining sends only a random ID and numbers — never your name, address, county or readings. Totals appear only after \(minimumParticipants) households join, so no one household can be picked out.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var communityProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community progress")
                .font(.headline)
            Text("\(shown.participants) \(shown.participants == 1 ? "household" : "households") taking part")
            if let totals = shown.totals {
                HStack(alignment: .firstTextBaseline) {
                    DataKindTag(isEstimate: false)
                    Text("\(totals.measuredGallonsSaved.gallonsText) gallons saved, from the meter readings of \(totals.measuredHouseholds) \(totals.measuredHouseholds == 1 ? "household" : "households")")
                }
                HStack(alignment: .firstTextBaseline) {
                    DataKindTag(isEstimate: true)
                    Text("\(totals.estimatedGallonsSaved.gallonsText) gallons, estimated from completed actions using EPA WaterSense averages")
                }
                ForEach(shown.actions) { action in
                    if let count = totals.actionsCompleted[action.id], count > 0 {
                        Text("• \(action.title): \(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Community totals appear once \(minimumParticipants) households join.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var yourParticipation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your part")
                .font(.headline)
            if let participation {
                ForEach(shown.actions) { action in
                    Toggle(isOn: Binding(
                        get: { participation.completedActions.contains(action.id) },
                        set: { done in toggle(action, done: done) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            if let gallons = action.estimatedGallons {
                                Text("Estimate: about \(gallons.gallonsText) gallons")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if shown.measuredByMeter {
                    HStack(alignment: .top) {
                        DataKindTag(isEstimate: false)
                        Text(measured.map { "You've saved about \($0.gallonsText) gallons compared with the 30 days before the challenge." }
                             ?? "Add meter readings (or a bill) from before and during the challenge to measure your savings.")
                            .font(.subheadline)
                    }
                }
                Button("Leave challenge", role: .destructive) {
                    Task { await send("leave", participation: participation) }
                }
                .font(.subheadline)
            } else {
                Text("Joining is optional. You can leave at any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await join() }
                } label: {
                    Text("Join this challenge")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.actionBlue)
                .disabled(isSending)
            }
            if isSending { ProgressView() }
            if let sendError {
                Text(sendError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .card()
    }

    private func join() async {
        let participation = ChallengeParticipation(challengeID: challenge.id)
        await send("join", participation: participation)
    }

    private func toggle(_ action: ChallengeAction, done: Bool) {
        guard var participation else { return }
        if done { participation.completedActions.insert(action.id) } else { participation.completedActions.remove(action.id) }
        store.challengeParticipation[challenge.id] = participation
        Task { await send("progress", participation: participation) }
    }

    private func send(_ action: String, participation: ChallengeParticipation) async {
        isSending = true
        defer { isSending = false }
        do {
            let list = try await AdvisorClient(settings: store.settings)
                .updateChallenge(action: action, participation: participation, measuredGallonsSaved: action == "leave" ? nil : measured)
            if action == "leave" {
                store.challengeParticipation[challenge.id] = nil
            } else {
                store.challengeParticipation[challenge.id] = participation
            }
            current = list.challenges.first { $0.id == challenge.id }
            onUpdate(list)
            sendError = nil
        } catch {
            sendError = error.localizedDescription
        }
    }
}

// MARK: - Action Center detail

struct ActionDetailView: View {
    var action: CitizenAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: action.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    Text(action.title)
                        .font(.title2.bold())
                    Text(action.summary)
                        .foregroundStyle(.secondary)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why it matters")
                        .font(.headline)
                    Text(action.whyItMatters)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("What you can do")
                        .font(.headline)
                    ForEach(Array(action.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.actionBlue, in: Circle())
                            Text(step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let phone = action.phone, let url = action.phoneURL {
                        Link(destination: url) {
                            Label("\(phone.label): \(phone.number)", systemImage: "phone.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.actionBlue)
                        .padding(.top, 4)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Official sources")
                        .font(.headline)
                    ForEach(action.sources, id: \.self) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                }
                .card()
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("Action Center")
        .navigationBarTitleDisplayMode(.inline)
    }
}
