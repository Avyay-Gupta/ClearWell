import SwiftUI

struct SettingsView: View {
    @Environment(WaterStore.self) private var store
    @State private var versionTaps = 0
    @State private var showDemoTools = false
    @State private var confirmErase = false
    @State private var connection: ConnectionState = .unknown
    @State private var remindersDenied = false

    enum ConnectionState: Equatable {
        case unknown, checking, ok(String), failed(String)
    }

    private var profile: Binding<HouseholdProfile> {
        Binding(get: { store.currentProfile }, set: { store.profile = $0 })
    }

    private var settings: Binding<AppSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Baby or pregnant person at home", isOn: profile.infantOrPregnant)
                Picker("Age of well", selection: profile.wellAge) {
                    ForEach(WellAge.allCases) { Text($0.label).tag($0) }
                }
                Picker("County", selection: profile.county) {
                    ForEach(County.allCases) { Text($0.fullName).tag($0) }
                }
            } header: {
                Text("Household")
            } footer: {
                Text("ClearWell uses these answers to explain what your results mean for your family.")
            }

            Section {
                Toggle("Remind me when a test is due", isOn: Binding(
                    get: { store.settings.remindersOn },
                    set: { turnOn in Task { await setReminders(turnOn) } }))
            } header: {
                Text("Reminders")
            } footer: {
                if remindersDenied {
                    Text("Notifications are turned off for ClearWell. Turn them on in the iPhone Settings app.")
                } else {
                    Text("Reminders follow the Minnesota Department of Health testing schedule.")
                }
            }

            Section {
                TextField("Server address", text: settings.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("App token (optional)", text: settings.appToken)
                Button("Test connection") {
                    Task { await checkConnection() }
                }
                switch connection {
                case .unknown: EmptyView()
                case .checking: ProgressView()
                case .ok(let message): Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let message): Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            } header: {
                Text("AI server")
            } footer: {
                Text("The ClearWell server talks to Claude for you. The API key stays on the server and is never stored on this phone.")
            }

            Section {
                NavigationLink("About & Privacy") { AboutPrivacyView() }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTaps += 1
                    if versionTaps >= 5 { withAnimation { showDemoTools = true } }
                }
            }

            if showDemoTools {
                Section {
                    Button("Load demo data") { store.loadDemoData() }
                    Button("Send a sample reminder in 5 seconds") {
                        Task {
                            if await ReminderScheduler.requestPermission() {
                                await ReminderScheduler.sendSampleReminder()
                            }
                        }
                    }
                    Button("Show welcome screens again") { store.profile = nil }
                    Button("Erase all data", role: .destructive) { confirmErase = true }
                } header: {
                    Text("Demo tools")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { store.eraseAll() }
        } message: {
            Text("All tests and your household answers will be removed from this phone.")
        }
    }

    private func setReminders(_ on: Bool) async {
        if on {
            let allowed = await ReminderScheduler.requestPermission()
            remindersDenied = !allowed
            store.settings.remindersOn = allowed
        } else {
            store.settings.remindersOn = false
        }
        await ReminderScheduler.reschedule(tests: store.tests, enabled: store.settings.remindersOn)
    }

    private func checkConnection() async {
        connection = .checking
        do {
            let health = try await AdvisorClient(settings: store.settings).health()
            connection = health.aiConfigured
                ? .ok("Connected. AI is ready.")
                : .failed("Connected, but the server has no Claude API key yet.")
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
