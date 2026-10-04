import SwiftUI

/// A bar showing where a measured value sits between the green, amber and red zones.
struct LimitBar: View {
    var value: Double
    var amberAt: Double?
    var redAt: Double
    var unit: String

    private var scaleMax: Double {
        max(redAt * 1.5, value * 1.15, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let amberX = width * (amberAt ?? redAt) / scaleMax
                let redX = width * redAt / scaleMax
                let markerX = min(max(width * value / scaleMax, 0), width)

                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.green.opacity(0.55)).frame(width: max(amberX - 2, 0))
                        if amberAt != nil {
                            Rectangle().fill(Color.orange.opacity(0.6)).frame(width: max(redX - amberX - 2, 0))
                        }
                        Rectangle().fill(Color.red.opacity(0.6))
                    }
                    .clipShape(Capsule())
                    .frame(height: 8)

                    Circle()
                        .fill(Color.primary)
                        .overlay(Circle().stroke(Color.cardBackground, lineWidth: 3))
                        .frame(width: 18, height: 18)
                        .offset(x: markerX - 9)
                }
                .frame(height: 18)
            }
            .frame(height: 18)

            HStack {
                Text("0")
                Spacer()
                Text("Limit \(redAt.formatted()) \(unit)")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.formatted()) \(unit), official limit \(redAt.formatted()) \(unit)")
    }
}
