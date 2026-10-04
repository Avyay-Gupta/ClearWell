import SwiftUI

extension WaterStatus {
    var color: Color {
        switch self {
        case .green: .green
        case .amber: .orange
        case .red: .red
        }
    }
}

extension Color {
    static let appBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
}

/// Rounded card with a soft shadow — the main building block of every screen.
/// An optional accent draws a colored stripe down the left edge (used for status).
struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var accent: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(padding)
            .padding(.leading, accent == nil ? 0 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(Color.cardBackground)
                    .overlay(alignment: .leading) {
                        if let accent {
                            Rectangle().fill(accent).frame(width: 6)
                        }
                    }
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            }
    }
}

extension View {
    func card(padding: CGFloat = 18, accent: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, accent: accent))
    }
}

/// Icon + words + color, so status is never shown by color alone.
struct StatusBadge: View {
    var status: WaterStatus
    var compact = false

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(status.color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(status.title)")
    }
}

/// Section title used above cards.
struct SectionTitle: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

/// The trust rule, shown wherever results appear.
struct TrustNote: View {
    var body: some View {
        Label("Colors come only from official EPA and MDH limits. AI explains the results but never decides if water is safe.", systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

extension Date {
    var longDate: String { formatted(date: .long, time: .omitted) }
}
