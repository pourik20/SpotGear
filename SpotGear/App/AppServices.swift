import Foundation
import Observation
import SwiftData

/// Composition root. Built once at launch and passed down through the SwiftUI environment.
@MainActor
@Observable
final class AppServices {
    let container: ModelContainer
    let library: SpotLibrary
    let cardImages: CardImageLoader
    let identifier: any VehicleIdentifier
    let catalog: VehicleCatalog
    let priceClassifier: any VehiclePriceClassifier
    let offersTestPhotos: Bool

    @ObservationIgnored private let repository: SwiftDataSpotRepository
    @ObservationIgnored private let media: FileMediaStore
    @ObservationIgnored private let segmenter: any ForegroundSegmenter
    @ObservationIgnored private let detector: any VehicleDetector

    init(
        container: ModelContainer,
        media: FileMediaStore,
        identifier: any VehicleIdentifier,
        segmenter: any ForegroundSegmenter,
        detector: any VehicleDetector,
        catalog: VehicleCatalog,
        priceClassifier: any VehiclePriceClassifier,
        offersTestPhotos: Bool,
        beforeSave: (() throws -> Void)? = nil
    ) throws {
        self.container = container
        self.media = media
        self.identifier = identifier
        self.segmenter = segmenter
        self.detector = detector
        self.catalog = catalog
        self.priceClassifier = priceClassifier
        self.offersTestPhotos = offersTestPhotos
        repository = try SwiftDataSpotRepository(container: container, catalog: catalog)
        repository.beforeSave = beforeSave
        cardImages = CardImageLoader(media: media)
        library = SpotLibrary(repository: repository, media: media, cardImages: cardImages)
    }

    func makeImportSession() -> ImportSession {
        ImportSession(
            media: media,
            repository: repository,
            worker: ImageWorker(identifier: identifier, segmenter: segmenter, detector: detector, media: media),
            identifier: identifier,
            catalog: catalog,
            priceClassifier: priceClassifier
        )
    }

    #if DEBUG
    /// Canvas uses an in-memory library and its own temporary media directory.
    static func preview() throws -> AppServices {
        try AppServices(
            container: try PersistenceController.makeInMemoryContainer(),
            media: FileMediaStore(rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("SpotGearPreviews", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)),
            identifier: FakeVehicleIdentifier(),
            segmenter: VisionForegroundSegmenter(),
            detector: FakeVehicleDetector(boxes: []),
            catalog: VehicleCatalog.bundled(),
            priceClassifier: NoPriceClassifier(),
            offersTestPhotos: true
        )
    }
    #endif

    /// Opens the store and media folder for this launch. Never resets an unreadable store.
    static func live(options: LaunchOptions = .current) throws -> AppServices {
        let storeURL: URL
        let mediaURL: URL
        if let sandbox = options.isolatedDataDirectory {
            if options.resetsIsolatedData { try? FileManager.default.removeItem(at: sandbox) }
            storeURL = sandbox.appendingPathComponent("SpotGear.store")
            mediaURL = sandbox.appendingPathComponent("Media", isDirectory: true)
        } else {
            storeURL = try PersistenceController.defaultStoreURL()
            mediaURL = try FileMediaStore.defaultRootURL()
        }

        let container = try PersistenceController.makeContainer(storeURL: storeURL)
        return try AppServices(
            container: container,
            media: FileMediaStore(rootURL: mediaURL),
            identifier: options.makeIdentifier(),
            segmenter: VisionForegroundSegmenter(),
            detector: options.makeDetector(),
            catalog: VehicleCatalog.bundled(),
            priceClassifier: options.makePriceClassifier(),
            offersTestPhotos: options.offersTestPhotos,
            beforeSave: options.makeSaveFault()
        )
    }
}
