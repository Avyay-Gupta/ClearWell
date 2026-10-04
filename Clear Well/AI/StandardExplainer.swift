import Foundation

/// Builds explanations on the phone from the limits table alone.
/// Used instantly while the AI is working, and whenever the server can't be reached.
/// Kept short on purpose: the full "why it matters" text lives under "Details and sources".
enum StandardExplainer {
    static func explain(_ reading: Reading, profile: HouseholdProfile, trend: Trend?) -> Explanation {
        let limit = reading.contaminant.limit
        let name = limit.name.lowercased()
        let status = OfficialLimits.status(for: reading.contaminant, value: reading.value, infantOrPregnantAtHome: profile.infantOrPregnant)
        var sentences: [String] = []

        // Lead with the household's most vulnerable people when it matters.
        if profile.infantOrPregnant, limit.infantsMostAtRisk, status != .green {
            sentences.append("This matters most in your home: \(limit.mostAtRisk.lowercasedFirst) are the most at risk.")
        }

        let officialLimit = limit.redLine(infantOrPregnantAtHome: profile.infantOrPregnant)
            .map { "the official limit of \(Reading.format($0, for: reading.contaminant))" } ?? "the official limit"

        switch (limit.kind, status) {
        case (.presence, .red):
            sentences.append("Your test found \(name).")
        case (.presence, _):
            sentences.append("No \(name) were found.")
        case (.amount, .red):
            sentences.append("Your \(name) is \(reading.formatted), above \(officialLimit).")
        case (.amount, .amber):
            sentences.append("Your \(name) is \(reading.formatted). That's under \(officialLimit), but high enough to keep an eye on.")
        case (.amount, .green):
            sentences.append("Your \(name) is \(reading.formatted), under \(officialLimit).")
        }

        if status == .red, let why = limit.whyItMatters.firstSentence {
            sentences.append(why)
        }
        if let trend, trend.points.count >= 2, limit.kind == .amount, trend.direction != .steady {
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

    /// The first sentence, using Foundation's sentence detection (handles quotes like `syndrome."`).
    var firstSentence: String? {
        var first: String?
        enumerateSubstrings(in: startIndex..., options: .bySentences) { substring, _, _, stop in
            first = substring?.trimmingCharacters(in: .whitespaces)
            stop = true
        }
        return first
    }

    /// Stops a line from breaking inside "10 mg/L" or between a number and its unit.
    var keepingUnitsTogether: String {
        var text = self
        for unit in ["mg/L", "µg/L"] {
            let glued = unit.replacingOccurrences(of: "/", with: "\u{2060}/\u{2060}")
            text = text.replacingOccurrences(of: " " + unit, with: "\u{00A0}" + glued)
            text = text.replacingOccurrences(of: unit, with: glued)
        }
        return text
    }
}
