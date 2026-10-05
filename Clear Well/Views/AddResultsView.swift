import PhotosUI
import SwiftUI

enum AddRoute: Hashable {
    case form(TestDraft)
    case results(WaterTest.ID)
}

/// Two ways in: scan the lab report, or type it in.
struct AddResultsView: View {
    @Environment(WaterStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanError: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.addPath) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Use the report you got back from your water testing lab.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    choiceCard(
                        icon: "doc.text.viewfinder",
                        title: "Scan my lab report",
                        detail: "Take a photo. ClearWell reads the numbers for you.") {
                        if cameraAvailable { showSourceChoice = true } else { showPhotoPicker = true }
                    }
                    .confirmationDialog("Scan my lab report", isPresented: $showSourceChoice, titleVisibility: .visible) {
                        Button("Take a photo") { showCamera = true }
                        Button("Choose from Photos") { showPhotoPicker = true }
                    }

                    choiceCard(
                        icon: "keyboard",
                        title: "Type it in",
                        detail: "Enter the numbers from your report in a simple form.") {
                        router.addPath.append(.form(TestDraft(county: store.currentProfile.county)))
                    }

                    Label("You'll check every number before anything is saved.", systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Add Results")
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .form(let draft):
                    TestFormView(initialDraft: draft)
                case .results(let id):
                    ResultsView(testID: id)
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await scan(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    scanError = "ClearWell couldn't open that photo. Try another one."
                    return
                }
                await scan(image)
            }
        }
        .overlay {
            if isScanning { ScanningOverlay() }
        }
        .alert("Couldn't read the report", isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
            Button("Type it in instead") {
                router.addPath.append(.form(TestDraft(county: store.currentProfile.county)))
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private func choiceCard(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func scan(_ image: UIImage) async {
        guard let jpeg = image.preparedForUpload() else {
            scanError = "ClearWell couldn't prepare that photo."
            return
        }
        isScanning = true
        defer { isScanning = false }
        do {
            let result = try await AdvisorClient(settings: store.settings).scan(jpegData: jpeg)
            let draft = TestDraft(scan: result, county: store.currentProfile.county)
            if draft.readings.isEmpty {
                scanError = "No water test results were found in this photo. Try a clearer, well-lit photo of the results page, or type the numbers in."
            } else {
                router.addPath.append(.form(draft))
            }
        } catch {
            scanError = error.localizedDescription
        }
    }
}

private struct ScanningOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading your lab report…")
                    .font(.headline)
                Text("This usually takes a few seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

extension UIImage {
    /// Shrinks large photos and converts them to JPEG so uploads stay small and fast.
    func preparedForUpload(maxDimension: CGFloat = 2000) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// The system camera, wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
