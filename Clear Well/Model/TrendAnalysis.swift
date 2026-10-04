import Foundation

/// Plain statistics on one contaminant across saved tests.
/// The math happens here, in code; the AI only explains the result.
struct Trend: Equatable {
    enum Direction: String {
        case rising, falling, steady
    }

    var points: [Point]
    var direction: Direction
    /// Percent change from the previous test to the latest test.
    var percentChange: Double?
    /// How many tests in a row the value went up (counting the latest).
    var consecutiveRises: Int
    var minimum: Double
    var maximum: Double

    struct Point: Equatable, Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var latest: Point? { points.last }

    /// "Up 29% since your previous test." — shown under the chart and sent to the AI.
    var summary: String {
        guard points.count >= 2, let change = percentChange else {
            return "Add another test to see a trend."
        }
        let percent = abs(change).formatted(.number.precision(.fractionLength(0)))
        var text: String
        switch direction {
        case .rising: text = "Up \(percent)% since your previous test."
        case .falling: text = "Down \(percent)% since your previous test."
        case .steady: text = "About the same as your previous test."
        }
        if consecutiveRises >= 2 {
            text += " It has gone up in each of your last \(consecutiveRises + 1) tests."
        }
        return text
    }
}

enum TrendAnalysis {
    /// Changes smaller than this (in percent) count as "steady".
    static let steadyThreshold = 10.0

    static func trend(for contaminant: Contaminant, tests: [WaterTest]) -> Trend? {
        let points = tests
            .compactMap { test in test.value(for: contaminant).map { Trend.Point(date: test.date, value: $0) } }
            .sorted { $0.date < $1.date }
        guard let first = points.first else { return nil }

        var percentChange: Double?
        var direction = Trend.Direction.steady
        if points.count >= 2 {
            let previous = points[points.count - 2].value
            let latest = points[points.count - 1].value
            if previous > 0 {
                percentChange = (latest - previous) / previous * 100
            } else if latest > 0 {
                percentChange = 100
            } else {
                percentChange = 0
            }
            if let change = percentChange {
                if change >= steadyThreshold { direction = .rising }
                else if change <= -steadyThreshold { direction = .falling }
            }
        }

        var rises = 0
        var index = points.count - 1
        while index > 0, points[index].value > points[index - 1].value {
            rises += 1
            index -= 1
        }

        let values = points.map(\.value)
        return Trend(
            points: points,
            direction: direction,
            percentChange: percentChange,
            consecutiveRises: rises,
            minimum: values.min() ?? first.value,
            maximum: values.max() ?? first.value)
    }
}
