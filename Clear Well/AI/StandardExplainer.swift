import Foundation

/// Builds explanations on the phone from the limits table alone.
/// Used instantly while the AI is working, and whenever the server can't be reached.
enum StandardExplainer {
    static func explain(_ reading: Reading, profile: HouseholdProfile, trend: Trend?) -> Explanation {
        let limit = reading.contaminant.limit
        let status = OfficialLimits.status(for: reading.contaminant, value: reading.value, infantOrPregnantAtHome: profile.infantOrPregnant)
        var sentences: [String] = []

        // Lead with the household's most vulnerable people when it matters.
        if profile.infantOrPregnant, limit.infantsMostAtRisk, status != .green {
            sentences.append("Because there is a baby or pregnant person in your home, this result matters most: \(limit.mostAtRisk.lowercasedFirst) are the most at risk.")
        }

        switch (limit.kind, status) {
        case (.presence, .red):
            sentences.append("Your test found \(limit.name.lowercased()).")
        case (.presence, _):
            sentences.append("No \(limit.name.lowercased()) were found.")
        case (.amount, .red):
            sentences.append("Your \(limit.name.lowercased()) is \(reading.formatted), at or above the official limit (\(limit.limitLabel)).")
        case (.amount, .amber):
            sentences.append("Your \(limit.name.lowercased()) is \(reading.formatted). That is below the red line, but high enough to keep an eye on (\(limit.limitLabel)).")
        case (.amount, .green):
            sentences.append("Your \(limit.name.lowercased()) is \(reading.formatted), well within official guidance (\(limit.limitLabel)).")
        }

        if status != .green {
            sentences.append(limit.whyItMatters)
        }
        if let trend, trend.points.count >= 2, limit.kind == .amount {
            sentences.append(trend.summary)
        }

        return Explanation(
            text: sentences.joined(separator: " "),
            nextStep: limit.nextSteps[status] ?? "",
            origin: .standard)
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
