import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var confirmsDeleteAll = false
    @State private var deleteFailed = false
    @State private var isDeleting = false

    var body: some View {
        Form {
            Section("Offline by Design") {
                Text("SpotGear works without an internet connection, account, or server. Your photos and collection are stored and processed on this device.")
            }
            .listRowBackground(Theme.panel)

            Section("Car Identification") {
                identificationStatus
                Text("Backgrounds are removed on your device using Apple's Vision framework where supported. Otherwise, cards use a photo crop.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.panel)

            Section("Pixel art") {
                Text("Pixel cards are created on your device by reducing your photo's resolution and color palette. No generative AI or uploads are involved, and the original photo is preserved.")
            }
            .listRowBackground(Theme.panel)

            Section("Data & Backups") {
                Text("Your collection is stored on this device and may be included in iCloud or computer backups. Deleting the app also deletes your collection.")
            }
            .listRowBackground(Theme.panel)

            Section {
                Button(role: .destructive) {
                    confirmsDeleteAll = true
                } label: {
                    HStack {
                        Label("Delete Collection", systemImage: "trash")
                        if isDeleting { Spacer(); PixelLoadingIndicator() }
                    }
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("settings.deleteAll")
            } footer: {
                if deleteFailed {
                    Text("Couldn't delete the collection. Your data is unchanged.")
                        .foregroundStyle(Theme.danger)
                }
            }
            .listRowBackground(Theme.panel)
        }
        .pixelListBackground()
        .navigationTitle("Settings")
        .confirmationDialog("Delete Your Collection?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete All Cars and Photos", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All cards, notes, and saved photos will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var identificationStatus: some View {
        switch services.identifier.availability {
        case .available where services.identifier.descriptor.providerID.hasPrefix("debug."):
            Label("Debug build: sample suggestions are shown instead of real identification results.", systemImage: "testtube.2")
        case .available where services.identifier.descriptor.providerID == SystemModelVehicleIdentifier.providerID:
            Label("Apple Intelligence suggests a make and model on your device without uploading photos. Suggestions may be inaccurate, so you always review and confirm them.", systemImage: "checkmark.circle")
        case .available:
            Label("An on-device identification model is available. You always review and confirm its suggestions.", systemImage: "checkmark.circle")
        case .unavailable(let reason):
            Label { IdentificationUnavailableText(reason: reason) } icon: { Image(systemName: "info.circle") }
        }
    }

    private func deleteAll() {
        isDeleting = true
        deleteFailed = false
        Task {
            do {
                try await services.library.deleteAll()
            } catch {
                deleteFailed = true
            }
            isDeleting = false
        }
    }
}
