import SwiftUI

/// First launch: a welcome screen and a few quick questions about the household.
struct OnboardingView: View {
    @Environment(WaterStore.self) private var store
    @State private var index = 0
    @State private var draft = HouseholdProfile()
    @State private var answeredSource = false
    @State private var answeredInfant = false
    @State private var answeredWellAge = false

    private enum Step {
        case welcome, waterSource, infant, wellAge, county
    }

    /// City-water homes skip the well-age question.
    private var steps: [Step] {
        draft.hasPrivateWell
            ? [.welcome, .waterSource, .infant, .wellAge, .county]
            : [.welcome, .waterSource, .infant, .county]
    }

    var body: some View {
        VStack(spacing: 0) {
            if index > 0 {
                header
            }

            Group {
                switch steps[min(index, steps.count - 1)] {
                case .welcome: welcome
                case .waterSource: waterSourceQuestion
                case .infant: infantQuestion
                case .wellAge: wellAgeQuestion
                case .county: countyQuestion
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .padding(.horizontal, 24)
        .background(Color.appBackground)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func next() {
        index = min(index + 1, steps.count - 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                index -= 1
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            Spacer()
            Text("Question \(index) of \(steps.count - 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            Image(systemName: "drop.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("ClearWell")
                    .font(.largeTitle.bold())
                Text("Understand your water test in plain English, use water wisely, and help protect the water your community shares.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                feature("checkmark.shield.fill", "Colors come only from official EPA and Minnesota Department of Health limits.")
                feature("sparkles", "AI explains what your results mean for your family.")
                feature("lock.fill", "Your test results and water use stay on this phone.")
            }
            .card()

            Spacer()

            Button {
                next()
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.actionBlue)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }

    private var waterSourceQuestion: some View {
        question(
            title: "Where does your home's water come from?",
            subtitle: "Private wells aren't tested by anyone but the owner. City water is tested by your water supplier. ClearWell helps with both.") {
            choice(WaterSource.privateWell.label, icon: "drop.circle", selected: answeredSource && draft.waterSource == .privateWell) {
                draft.waterSource = .privateWell
                answeredSource = true
                next()
            }
            choice(WaterSource.municipal.label, icon: "building.2", selected: answeredSource && draft.waterSource == .municipal) {
                draft.waterSource = .municipal
                answeredSource = true
                next()
            }
        }
    }

    private var infantQuestion: some View {
        question(
            title: "Is there a baby or a pregnant person in your home?",
            subtitle: "Some contaminants, like nitrate, are most dangerous for babies. This helps ClearWell explain what matters most for your family.") {
            choice("Yes", icon: "figure.and.child.holdinghands", selected: answeredInfant && draft.infantOrPregnant) {
                draft.infantOrPregnant = true
                answeredInfant = true
                next()
            }
            choice("No", icon: "person.2", selected: answeredInfant && !draft.infantOrPregnant) {
                draft.infantOrPregnant = false
                answeredInfant = true
                next()
            }
        }
    }

    private var wellAgeQuestion: some View {
        question(
            title: "About how old is your well?",
            subtitle: "Older wells can be more likely to let surface water in.") {
            ForEach(WellAge.allCases) { age in
                choice(age.label, icon: "calendar", selected: answeredWellAge && draft.wellAge == age) {
                    draft.wellAge = age
                    answeredWellAge = true
                    next()
                }
            }
        }
    }

    private var countyQuestion: some View {
        question(
            title: "Which county do you live in?",
            subtitle: "ClearWell shows local water conditions, testing labs and experts near you.") {
            ForEach(County.allCases) { county in
                choice(county.fullName, icon: "mappin.and.ellipse", selected: false) {
                    draft.county = county
                    store.profile = draft
                }
            }
        }
    }

    // MARK: - Building blocks

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
    }

    private func question<Choices: View>(title: String, subtitle: String, @ViewBuilder choices: () -> Choices) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    choices()
                }
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func choice(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .card(padding: 16)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview {
    OnboardingView()
        .environment(WaterStore(fileURL: URL.temporaryDirectory.appending(path: "preview.json")))
}
