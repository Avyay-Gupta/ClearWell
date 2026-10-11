import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  COMMUNITY CONSERVATION CHALLENGES
//
//  Challenges are defined on the ClearWell server so everyone sees the same
//  ones. Joining is optional. The phone sends only a random ID plus numbers
//  (gallons saved, which actions were done) — never names, addresses or
//  readings. The server shows totals only once enough households join, and
//  keeps measured savings (from meters) separate from estimated savings.
// ─────────────────────────────────────────────────────────────────────────────

struct ChallengeAction: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// Estimated gallons saved by doing this once during the challenge, or nil if there's no reliable estimate.
    var estimatedGallons: Double?
}

struct ChallengeTotals: Codable, Hashable {
    var measuredHouseholds: Int
    var measuredGallonsSaved: Double
    var estimatedGallonsSaved: Double
    var actionsCompleted: [String: Int]
}

struct Challenge: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var whyItMatters: String
    var startDate: String
    var endDate: String
    /// True if progress can be measured from meter readings or bills.
    var measuredByMeter: Bool
    var actions: [ChallengeAction]
    var participants: Int
    /// Present only once at least `minimumParticipants` households have joined.
    var totals: ChallengeTotals?

    var start: Date? { Challenge.dayFormatter.date(from: startDate) }
    /// End of the last day.
    var end: Date? { Challenge.dayFormatter.date(from: endDate).map { $0.addingTimeInterval(86_400) } }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct ChallengeList: Codable {
    var challenges: [Challenge]
    var minimumParticipants: Int
}

/// This household's participation, saved only on this phone.
struct ChallengeParticipation: Codable, Hashable {
    var challengeID: String
    /// Random ID shared with the server instead of anything personal.
    var participantID = UUID()
    var joinedAt = Date.now
    var completedActions: Set<String> = []
}

enum ChallengeMath {
    /// Gallons saved during the challenge compared with the 30 days before it,
    /// measured from this household's own readings. Nil if there isn't enough data.
    static func measuredSavings(challenge: Challenge, intervals: [UsageInterval], now: Date = .now) -> Double? {
        guard challenge.measuredByMeter, let start = challenge.start, let end = challenge.end,
              let latest = intervals.map(\.end).max(), latest > start else { return nil }
        let before = start.addingTimeInterval(-30 * 86_400)..<start
        let during = start..<min(end, latest, now)
        guard let baseline = UsageAnalysis.averageGallonsPerDay(in: before, intervals: intervals),
              let current = UsageAnalysis.averageGallonsPerDay(in: during, intervals: intervals) else { return nil }
        let days = during.upperBound.timeIntervalSince(during.lowerBound) / 86_400
        return max(0, (baseline - current) * days)
    }

    /// Estimated gallons from the actions this household marked done.
    static func estimatedSavings(challenge: Challenge, completed: Set<String>) -> Double {
        challenge.actions.filter { completed.contains($0.id) }.compactMap(\.estimatedGallons).reduce(0, +)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RESPONSIBLE-CITIZEN ACTION CENTER
//  Each action explains why it matters, not just what to do. Links and phone
//  numbers were checked on the official sites in Oct 2026.
// ─────────────────────────────────────────────────────────────────────────────

struct CitizenAction: Identifiable, Hashable {
    var id: String
    var title: String
    var icon: String
    var summary: String
    var whyItMatters: String
    var steps: [String]
    var sources: [SourceLink]
    var phone: (label: String, number: String)?

    static func == (lhs: CitizenAction, rhs: CitizenAction) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var phoneURL: URL? {
        phone.flatMap { URL(string: "tel:\($0.number.filter(\.isNumber))") }
    }
}

enum ActionCenter {
    static let actions: [CitizenAction] = [
        CitizenAction(
            id: "well-care",
            title: "Test and care for your well",
            icon: "drop.circle.fill",
            summary: "Follow MDH's testing schedule and keep your well in good shape.",
            whyItMatters: "No agency tests private wells, so the owner is the only safeguard. A cracked cap or water pooling around the well can let surface water carry bacteria and nitrate straight into the groundwater your neighbors share.",
            steps: [
                "Test for coliform bacteria every year and nitrate every other year; test for arsenic and lead at least once.",
                "Check that the well cap is secure and the casing isn't cracked, and keep the top at least 1 foot above the ground.",
                "Keep fertilizer, fuel and chemicals away from the well, and don't let water pond around it.",
                "Have a licensed well contractor seal any unused well on your property.",
            ],
            sources: [
                SourceLink(title: "MDH: Owner's Guide to Wells", url: URL(string: "https://www.health.state.mn.us/communities/environment/water/wells/waterquality/test.html")!),
            ]),
        CitizenAction(
            id: "runoff",
            title: "Cut fertilizer and chemical runoff",
            icon: "leaf.fill",
            summary: "Use less fertilizer and keep chemicals and yard waste out of storm drains.",
            whyItMatters: "Extra fertilizer washes into lakes and streams, where phosphorus feeds algae blooms. Nitrogen can soak down into groundwater as nitrate — the same nitrate that is dangerous for babies in well water.",
            steps: [
                "Use phosphorus-free lawn fertilizer, and only as much as your lawn needs.",
                "Keep grass clippings and leaves out of the street and away from storm drains.",
                "Take paints, solvents, used oil and pesticides to your county's household hazardous waste collection.",
                "Point downspouts onto your lawn or into a rain barrel instead of the driveway.",
            ],
            sources: [
                SourceLink(title: "MPCA: Residential pollution prevention", url: URL(string: "https://stormwater.pca.state.mn.us/residential_pollution_prevention_methods")!),
                SourceLink(title: "MDA: Nitrogen and groundwater protection", url: URL(string: "https://www.mda.state.mn.us/nfr")!),
            ]),
        CitizenAction(
            id: "dry-periods",
            title: "Use water wisely in dry periods",
            icon: "sun.max.fill",
            summary: "Water less outdoors when drought hits.",
            whyItMatters: "In a drought, lakes, streams and wells all draw on the same shrinking supply. Lawn watering is often the biggest household use in summer, so small changes across a community add up.",
            steps: [
                "Water established lawns about 1 inch every 10 to 14 days during drought, in the morning.",
                "Skip watering when rain is forecast — check the Local Water dashboard.",
                "Fix leaks and follow any local watering restrictions.",
            ],
            sources: [
                SourceLink(title: "Minnesota DNR: Drought", url: URL(string: "https://www.dnr.state.mn.us/climate/drought/index.html")!),
                SourceLink(title: "UMN Extension: Water-saving strategies for lawns", url: URL(string: "https://extension.umn.edu/lawn-care/water-saving-strategies-home-lawns")!),
            ]),
        CitizenAction(
            id: "stormwater",
            title: "Learn how stormwater works",
            icon: "cloud.rain.fill",
            summary: "What goes down a storm drain goes straight to a lake or stream.",
            whyItMatters: "Storm drains usually aren't connected to a treatment plant. Rain carries whatever is on streets and driveways — oil, salt, soap, pet waste, leaves — directly into local water.",
            steps: [
                "Sweep driveways instead of hosing them into the street.",
                "Wash cars on the grass or at a car wash.",
                "Use de-icing salt sparingly and shovel first.",
                "Pick up pet waste and litter.",
            ],
            sources: [
                SourceLink(title: "MPCA: Residential pollution prevention", url: URL(string: "https://stormwater.pca.state.mn.us/residential_pollution_prevention_methods")!),
            ]),
        CitizenAction(
            id: "events",
            title: "Join local water-protection events",
            icon: "person.3.fill",
            summary: "Volunteer with your Soil and Water Conservation District.",
            whyItMatters: "Cleanups, tree plantings, lake monitoring and well-testing clinics depend on volunteers. Taking part also connects you with the people managing your local water.",
            steps: [
                "Find your county's Soil and Water Conservation District and check its events.",
                "Volunteer with the MPCA's Citizen Lake or Stream Monitoring Program.",
                "Watch for free well-testing clinics in your county.",
            ],
            sources: [
                SourceLink(title: "Find your Soil & Water Conservation District", url: URL(string: "https://www.maswcd.org/")!),
                SourceLink(title: "MPCA: Surface water data and monitoring", url: URL(string: "https://www.pca.state.mn.us/eda-surface-water-data")!),
            ]),
        CitizenAction(
            id: "report",
            title: "Report environmental concerns",
            icon: "exclamationmark.bubble.fill",
            summary: "Spills and pollution reports go to the Minnesota Duty Officer, any time.",
            whyItMatters: "Fast reports let state agencies contain a spill before it reaches wells, lakes or streams. Minnesota law requires reporting spills that could pollute water.",
            steps: [
                "For a spill or release, call the Minnesota Duty Officer (24 hours a day).",
                "Be ready to say where it happened, what spilled, about how much, and whether it reached water or a storm drain.",
                "For a possible problem with your well, call the MDH Well Management Section.",
            ],
            sources: [
                SourceLink(title: "MPCA: Emergency response", url: URL(string: "https://www.pca.state.mn.us/about-mpca/emergency-response")!),
            ],
            phone: (label: "Call the Minnesota Duty Officer", number: "800-422-0798")),
        CitizenAction(
            id: "decisions",
            title: "Follow local water decisions",
            icon: "building.columns.fill",
            summary: "Learn about your watershed's plan and have a say.",
            whyItMatters: "Counties and watershed groups decide which projects get funded — from well sealing to wetland restoration. Public meetings and comment periods are where residents can shape those choices.",
            steps: [
                "Look up your watershed's One Watershed, One Plan.",
                "Check your county's water plan and board meeting agendas.",
                "Share your concerns during public comment periods.",
            ],
            sources: [
                SourceLink(title: "BWSR: One Watershed, One Plan", url: URL(string: "https://bwsr.state.mn.us/one-watershed-one-plan")!),
            ]),
    ]
}
