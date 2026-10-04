import SwiftUI

/// Labs and well experts, with the user's county first.
struct GetHelpView: View {
    @Environment(WaterStore.self) private var store

    private var county: County { store.currentProfile.county }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Your county", selection: Binding(
                        get: { county },
                        set: { newValue in
                            var profile = store.currentProfile
                            profile.county = newValue
                            store.profile = profile
                        })) {
                        ForEach(County.allCases) { Text($0.fullName).tag($0) }
                    }
                }

                let countyResources = LocalResources.resources(for: county)
                if !countyResources.isEmpty {
                    Section {
                        ForEach(countyResources) { ResourceRow(resource: $0) }
                    } header: {
                        Text("Near you · \(county.fullName)")
                    } footer: {
                        if LocalResources.countyContacts[county] == nil {
                            Text("County environmental health contacts are coming soon.")
                        }
                    }
                }

                Section("Minnesota statewide") {
                    ForEach(LocalResources.statewide) { ResourceRow(resource: $0) }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("ClearWell is not a substitute for a certified lab or the Minnesota Department of Health. If anyone is sick, contact a doctor.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Get Help")
        }
    }
}

struct ResourceRow: View {
    var resource: LocalResource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.name)
                        .font(.headline)
                    Text(resource.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let phone = resource.phone {
                        Text(phone)
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }

            HStack(spacing: 8) {
                if let url = resource.phoneURL {
                    action("Call", "phone.fill", url)
                }
                if let email = resource.email, let url = URL(string: "mailto:\(email)") {
                    action("Email", "envelope.fill", url)
                }
                if let url = resource.mapsURL {
                    action(resource.address == nil ? "Open Maps" : "Directions", "map.fill", url)
                }
                if let url = resource.website {
                    action("Website", "safari.fill", url)
                }
            }
            .padding(.leading, 40)
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch resource.kind {
        case .state: "building.columns.fill"
        case .county: "mappin.and.ellipse"
        case .labSearch: "testtube.2"
        }
    }

    private func action(_ title: String, _ systemImage: String, _ url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.borderless)
    }
}
