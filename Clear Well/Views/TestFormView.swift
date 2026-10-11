import SwiftUI

/// The Add Results form. Scanned values arrive pre-filled and must each be confirmed.
struct TestFormView: View {
    @Environment(WaterStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var draft: TestDraft
    @FocusState private var focused: Contaminant?

    init(initialDraft: TestDraft) {
        _draft = State(initialValue: initialDraft)
    }

    private var isScanned: Bool { draft.entry == .scanned }

    var body: some View {
        Form {
            if isScanned {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Check every number")
                                .font(.headline)
                            Text("ClearWell read these from your photo. Compare each one with your paper report, fix anything that's wrong, then tap Confirm.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "eye.fill").foregroundStyle(.tint)
                    }
                    ForEach(draft.scanNotes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Test details") {
                DatePicker("Test date", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                Picker("County", selection: $draft.county) {
                    ForEach(County.allCases) { Text($0.fullName).tag($0) }
                }
                TextField("Lab name (optional)", text: $draft.labName)
                    .textInputAutocapitalization(.words)
            }

            Section {
                ForEach(TestDraft.amountContaminants) { contaminant in
                    valueRow(contaminant)
                }
            } header: {
                Text("Results")
            } footer: {
                Text("Leave blank anything your lab didn't test. If your report says \"not detected\" or \"<\", enter 0.")
            }

            Section("Bacteria") {
                Picker("Coliform bacteria", selection: $draft.coliform) {
                    ForEach(ColiformChoice.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: draft.coliform) { draft.needsConfirmation.remove(.coliform) }
                if draft.needsConfirmation.contains(.coliform) {
                    confirmButton(.coliform)
                }
                if draft.coliform != .notTested, let status = draft.readings.first(where: { $0.contaminant == .coliform }).map({ OfficialLimits.status(for: .coliform, value: $0.value) }) {
                    StatusBadge(status: status, compact: true)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Save test")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(draft.problem != nil)
            } footer: {
                if let problem = draft.problem {
                    Text(problem)
                }
            }
        }
        .navigationTitle(isScanned ? "Review scan" : "Type it in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    private func valueRow(_ contaminant: Contaminant) -> some View {
        let limit = contaminant.limit
        let text = Binding(
            get: { draft.values[contaminant, default: ""] },
            set: { draft.values[contaminant] = $0 })
        let needsCheck = draft.needsConfirmation.contains(contaminant)
        let value = TestDraft.parse(text.wrappedValue)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(limit.name)
                    Text(limit.limitLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 90)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(needsCheck ? Color.yellow.opacity(0.25) : Color(.tertiarySystemFill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(draft.isInvalid(contaminant) ? Color.red : .clear, lineWidth: 1.5))
                    .focused($focused, equals: contaminant)
                    .accessibilityLabel("\(limit.name) in \(limit.unit)")
                Text(limit.unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }

            HStack {
                if let value {
                    StatusBadge(status: OfficialLimits.status(for: contaminant, value: value, infantOrPregnantAtHome: store.currentProfile.infantOrPregnant), compact: true)
                } else if draft.isInvalid(contaminant) {
                    Text("Enter a number, like 4.2")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                if needsCheck {
                    confirmButton(contaminant)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmButton(_ contaminant: Contaminant) -> some View {
        Button {
            draft.needsConfirmation.remove(contaminant)
        } label: {
            Label("Confirm", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Confirm \(contaminant.name)")
    }

    private func save() {
        guard draft.problem == nil else { return }
        let test = draft.makeTest()
        store.add(test)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        router.qualityPath = [.results(test.id)]
    }
}
