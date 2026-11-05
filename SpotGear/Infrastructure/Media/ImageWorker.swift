import CoreGraphics
import Foundation

struct RegionJob: Equatable, Sendable {
    var importID: UUID
    var regionID: UUID
    var revision: Int
    var crop: CropRect
}

struct RegionProcessingResult: Equatable, Sendable {
    var importID: UUID
    var regionID: UUID
    var revision: Int
    var identification: IdentificationState
    var segmentation: SegmentationState
}

/// Runs decoding, inference and rendering off the main actor. Keeps a single working copy of the source.
actor ImageWorker {
    static let workingMaxPixelSize = 2048

    private let identifier: any VehicleIdentifier
    private let segmenter: any ForegroundSegmenter
    private let detector: any VehicleDetector
    private let media: any MediaStore
    private var working: (url: URL, image: CGImage)?

    init(
        identifier: any VehicleIdentifier,
        segmenter: any ForegroundSegmenter,
        detector: any VehicleDetector,
        media: any MediaStore
    ) {
        self.identifier = identifier
        self.segmenter = segmenter
        self.detector = detector
        self.media = media
    }

    func loadWorkingImage(from url: URL) throws -> CGImage {
        if let working, working.url == url { return working.image }
        let image = try ImageCoding.downsampledImage(at: url, maxPixelSize: Self.workingMaxPixelSize)
        working = (url, image)
        return image
    }

    /// A failed detection is not an import error: the user marks the cars by hand instead.
    func detectVehicles(sourceURL: URL) async throws -> VehicleDetectionOutcome {
        let image = try loadWorkingImage(from: sourceURL)
        do {
            return try await detector.detect(image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable
        }
    }

    /// Returns nil when cancelled. Identification and segmentation fail independently.
    func process(_ job: RegionJob, sourceURL: URL) async -> RegionProcessingResult? {
        guard !Task.isCancelled else { return nil }
        guard let image = try? loadWorkingImage(from: sourceURL),
              let crop = CardRenderer.crop(image, to: job.crop)
        else {
            return RegionProcessingResult(
                importID: job.importID, regionID: job.regionID, revision: job.revision,
                identification: .failed, segmentation: .notUsable(.failed)
            )
        }

        let identification: IdentificationState
        do {
            identification = .finished(try await identifier.identify(crop))
        } catch is CancellationError {
            return nil
        } catch {
            identification = .failed
        }
        guard !Task.isCancelled else { return nil }

        let segmentation: SegmentationState
        do {
            switch try await segmenter.segment(crop) {
            case .cutout(let cutout):
                let name = "\(job.regionID.uuidString)-r\(job.revision)-cutout.png"
                let polished = CutoutEnhancer.enhanced(cutout)
                try await media.stageFile(try ImageCoding.png(polished), named: name, importID: job.importID)
                segmentation = .available(stagedFileName: name)
            case .notUsable(let reason):
                segmentation = .notUsable(reason)
            }
        } catch is CancellationError {
            return nil
        } catch {
            segmentation = .notUsable(.failed)
        }
        guard !Task.isCancelled else { return nil }

        return RegionProcessingResult(
            importID: job.importID, regionID: job.regionID, revision: job.revision,
            identification: identification, segmentation: segmentation
        )
    }

    /// Renders card thumbnails from the full normalized source, decoding it once.
    func renderThumbnails(sourceURL: URL, crops: [(id: UUID, crop: CropRect)]) throws -> [UUID: Data] {
        let source = try ImageCoding.downsampledImage(at: sourceURL, maxPixelSize: FileMediaStore.sourceMaxPixelSize)
        var result: [UUID: Data] = [:]
        for item in crops {
            guard let thumbnail = CardRenderer.thumbnail(from: source, crop: item.crop) else {
                throw MediaError.undecodable
            }
            result[item.id] = try ImageCoding.jpeg(thumbnail, quality: 0.85)
        }
        return result
    }

    func reset() {
        working = nil
    }
}
