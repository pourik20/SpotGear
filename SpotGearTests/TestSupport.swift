import CoreGraphics
import Foundation
import ImageIO
import SwiftData
@testable import SpotGear

struct TimeoutError: Error {}

/// Polls a main-actor condition; used to wait for asynchronous session transitions.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TimeoutError() }
        try await Task.sleep(for: .milliseconds(10))
    }
}

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SpotGearTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func fileCount(in directory: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
}

/// Releases waiting identification calls on demand, to exercise stale results deterministically.
actor Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var waiterCount = 0

    func wait() async {
        waiterCount += 1
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

struct StubIdentifier: VehicleIdentifier {
    var outcome: IdentificationOutcome = .available([
        VehicleCandidate(label: "a", make: "Škoda", model: "Octavia", generation: "III", score: 0.7),
        VehicleCandidate(label: "b", make: "Volkswagen", model: "Golf", generation: nil, score: 0.2),
    ])
    var gate: Gate?

    var descriptor: IdentifierDescriptor {
        IdentifierDescriptor(providerID: "test.stub", modelVersion: "1", labelMapVersion: "1")
    }

    var availability: IdentifierAvailability {
        if case .unavailable(let reason) = outcome { return .unavailable(reason) }
        return .available
    }

    func identify(_ image: CGImage) async throws -> IdentificationOutcome {
        if let gate { await gate.wait() }
        return outcome
    }
}

/// Returns the crop itself as a "cutout" so tests do not depend on Vision availability.
struct StubSegmenter: ForegroundSegmenter {
    var usable = true

    func segment(_ image: CGImage) async throws -> SegmentationOutcome {
        usable ? .cutout(image) : .notUsable(.ambiguous)
    }
}

struct StubDetector: VehicleDetector {
    var outcome: VehicleDetectionOutcome = .found([])

    func detect(_ image: CGImage) async throws -> VehicleDetectionOutcome { outcome }
}

/// A disk-backed store and media folder in a fresh temporary directory.
@MainActor
final class Harness {
    let root: URL
    let media: FileMediaStore
    let container: ModelContainer
    let repository: SwiftDataSpotRepository

    var storeURL: URL { root.appendingPathComponent("SpotGear.store") }
    var mediaURL: URL { root.appendingPathComponent("Media", isDirectory: true) }

    init(root: URL = makeTemporaryDirectory(), availableCapacity: @escaping @Sendable (URL) -> Int64? = { _ in nil }) throws {
        self.root = root
        media = FileMediaStore(rootURL: root.appendingPathComponent("Media", isDirectory: true), availableCapacity: availableCapacity)
        container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("SpotGear.store"))
        repository = SwiftDataSpotRepository(container: container)
    }

    func makeSession(
        identifier: any VehicleIdentifier = StubIdentifier(),
        segmenter: any ForegroundSegmenter = StubSegmenter(),
        detector: any VehicleDetector = StubDetector()
    ) -> ImportSession {
        ImportSession(
            media: media,
            repository: repository,
            worker: ImageWorker(identifier: identifier, segmenter: segmenter, detector: detector, media: media),
            identifier: identifier
        )
    }

    /// Starts a session with the three-car fixture and waits for the selection phase.
    func loadedSession(
        identifier: any VehicleIdentifier = StubIdentifier(),
        segmenter: any ForegroundSegmenter = StubSegmenter(),
        detector: any VehicleDetector = StubDetector(),
        data: Data = FixtureImageFactory.threeCarsJPEG()
    ) async throws -> ImportSession {
        let session = makeSession(identifier: identifier, segmenter: segmenter, detector: detector)
        session.start { data }
        try await waitUntil {
            session.phase == .selecting || session.phase == .reviewing || session.loadError != nil
        }
        return session
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<T>())
    }

    func stagingDirectory(_ importID: UUID) -> URL {
        mediaURL.appendingPathComponent("staging").appendingPathComponent(importID.uuidString)
    }
}

/// RGBA pixel of a normalized image at a pixel position (top-left origin).
func pixel(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return (data[0], data[1], data[2])
}

func decode(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
