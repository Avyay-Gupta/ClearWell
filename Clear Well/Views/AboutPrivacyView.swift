import SwiftUI

/// Step 12: trust and privacy, visible inside the app.
struct AboutPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                block("lock.fill", "Your data stays on this phone",
                      "Your test results and household answers are saved only on this phone. Nothing is shared unless you choose to scan a report or ask for an explanation.")

                block("checkmark.shield.fill", "Colors come from official limits",
                      "Green, amber and red come only from a fixed table of official limits from the U.S. Environmental Protection Agency (EPA) and the Minnesota Department of Health (MDH). The AI can never change a color.")

                block("sparkles", "AI explains — it never decides",
                      "ClearWell uses Claude, an AI model made by Anthropic, for two jobs: reading the numbers from a photo of your lab report (you check every number before it's saved), and explaining your results in plain English. It does not diagnose anyone or decide whether your water is safe.")

                block("paperplane.fill", "What is sent to the AI",
                      "When you scan a report, the photo is sent to the ClearWell server and on to Claude so the numbers can be read. When you view results, the numbers, their colors and your three household answers are sent (including your county) so the explanation fits your family. ClearWell never asks for or sends your name or address.")

                block("cross.case.fill", "Not a substitute for experts",
                      "ClearWell is not a substitute for a certified lab or the Minnesota Department of Health. For anything marked red, contact MDH or a certified lab. If anyone is sick, contact a doctor.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Official sources")
                        .font(.headline)
                    ForEach(OfficialLimits.generalSources, id: \.self) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                }
                .card()

                Text("Made for the Congressional App Challenge · Minnesota's 6th District")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("About & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}
