import AVFoundation
import PhotosUI
import SwiftUI

enum AppRoute: Hashable {
    case spot(UUID)
    case settings
    case quests
}

/// Hosts the collection and owns presentation of photo sources and the import flow.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @State private var path: [AppRoute] = []
    @State private var importSession: ImportSession?
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var cameraProblem: CameraProblem?
    @State private var importError: ImportError?
    @State private var capturedImage: UIImage?

    var body: some View {
        NavigationStack(path: $path) {
            CollectionView(actions: addActions)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .spot(let id): SpotDetailView(spotID: id)
                    case .settings: SettingsView()
                    case .quests: QuestsView()
                    }
                }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            startImport(capturedAtFallback: nil) {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaError.undecodable }
                return data
            }
        }
        .fullScreenCover(isPresented: $showsCamera, onDismiss: startCameraImport) {
            CameraPicker { image in
                capturedImage = image
                showsCamera = false
            } onCancel: {
                showsCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $importSession) { session in
            ImportFlowView(session: session) { outcome in
                importSession = nil
                if case .failed(let error) = outcome { importError = error }
            }
        }
        .alert(item: $cameraProblem) { problem in
            Alert(
                title: Text(problem.title),
                message: Text(problem.message),
                primaryButton: .default(Text("Vybrat z knihovny")) { showsPhotoPicker = true },
                secondaryButton: problem == .denied
                    ? .default(Text("Otevřít Nastavení")) { openSettings() }
                    : .cancel(Text("Zavřít"))
            )
        }
        .alert(
            importError?.title ?? "",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
            presenting: importError
        ) { _ in
            Button("Vybrat jinou fotografii") { showsPhotoPicker = true }
            Button("Zavřít", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .task { await services.library.sweepOrphanedMedia() }
    }

    private var addActions: AddPhotoActions {
        AddPhotoActions(
            takePhoto: requestCamera,
            choosePhoto: { showsPhotoPicker = true },
            useTestPhoto: testPhotoAction
        )
    }

    private var testPhotoAction: (() -> Void)? {
        #if DEBUG
        guard services.offersTestPhotos else { return nil }
        return { startImport(capturedAtFallback: nil) { FixtureImageFactory.bundledTestPhoto() ?? FixtureImageFactory.threeCarsJPEG() } }
        #else
        return nil
        #endif
    }

    /// Runs after the camera is dismissed so the import flow is not presented over a closing cover.
    private func startCameraImport() {
        guard let image = capturedImage else { return }
        capturedImage = nil
        startImport(capturedAtFallback: Date()) {
            guard let data = image.jpegData(compressionQuality: 0.95) else { throw MediaError.undecodable }
            return data
        }
    }

    private func startImport(capturedAtFallback: Date?, loader: @escaping @Sendable () async throws -> Data) {
        guard importSession == nil else { return }
        let session = services.makeImportSession()
        session.start(capturedAtFallback: capturedAtFallback, loader: loader)
        importSession = session
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraProblem = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showsCamera = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    showsCamera = true
                } else {
                    cameraProblem = .denied
                }
            }
        default:
            cameraProblem = .denied
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

enum CameraProblem: String, Identifiable {
    case unavailable
    case denied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unavailable: String(localized: "Fotoaparát není dostupný")
        case .denied: String(localized: "Přístup k fotoaparátu není povolen")
        }
    }

    var message: String {
        switch self {
        case .unavailable:
            String(localized: "Na tomto zařízení nelze použít fotoaparát. Fotografii můžete vybrat z knihovny.")
        case .denied:
            String(localized: "Přístup k fotoaparátu můžete povolit v Nastavení. Mezitím můžete vybrat fotografii z knihovny.")
        }
    }
}

/// Stand-in shown when the store cannot be opened. The store is never reset automatically.
struct StoreErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Sbírku nelze otevřít", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Databázi sbírky se nepodařilo otevřít. Data nebyla smazána ani přepsána. Zkuste aplikaci ukončit a spustit znovu, případně ji aktualizovat.")
        }
    }
}

#if DEBUG
private struct RootPreview: View {
    @State private var services: Result<AppServices, Error> = Result {
        PixelFonts.register()
        ThemeAppearance.apply()
        return try AppServices.preview()
    }

    var body: some View {
        Group {
            switch services {
            case .success(let services):
                RootView()
                    .environment(services)
                    .modelContainer(services.container)
            case .failure(let error):
                ContentUnavailableView("Náhled nelze otevřít", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            }
        }
        .preferredColorScheme(.dark)
        .font(.system(.body, design: .rounded))
        .tint(Theme.gold)
    }
}

#Preview("SpotGear – Sbírka") {
    RootPreview()
}
#endif
