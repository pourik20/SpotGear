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
                primaryButton: .default(Text("Choose from Library")) { showsPhotoPicker = true },
                secondaryButton: problem == .denied
                    ? .default(Text("Open Settings")) { openSettings() }
                    : .cancel(Text("Close"))
            )
        }
        .alert(
            importError?.title ?? "",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
            presenting: importError
        ) { _ in
            Button("Choose Another Photo") { showsPhotoPicker = true }
            Button("Close", role: .cancel) {}
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
        case .unavailable: String(localized: "Camera Unavailable")
        case .denied: String(localized: "Camera Access Required")
        }
    }

    var message: String {
        switch self {
        case .unavailable:
            String(localized: "The camera isn't available on this device. Choose a photo from your library instead.")
        case .denied:
            String(localized: "Allow camera access in Settings, or choose a photo from your library.")
        }
    }
}

/// Stand-in shown when the store cannot be opened. The store is never reset automatically.
struct StoreErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Unable to Open Collection", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Couldn't open your collection's database. Your data hasn't been deleted or overwritten. Try restarting or updating the app.")
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
                ContentUnavailableView("Unable to Open Preview", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            }
        }
        .preferredColorScheme(.dark)
        .font(.system(.body, design: .rounded))
        .tint(Theme.gold)
    }
}

#Preview("SpotGear – Collection") {
    RootPreview()
}
#endif
