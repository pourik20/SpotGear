#if DEBUG
import CoreGraphics
import Foundation

/// Deterministic test double for previews and UI tests. Not compiled into release builds.
/// Its suggestions are labelled as test data in the UI.
struct FakeVehicleIdentifier: VehicleIdentifier {
    static let providerID = "debug.fake-identifier"

    var candidates: [VehicleCandidate] = [
        VehicleCandidate(label: "test.skoda.octavia", make: "Škoda", model: "Octavia", generation: "III", score: 0.6),
        VehicleCandidate(label: "test.vw.golf", make: "Volkswagen", model: "Golf", generation: "VII", score: 0.3),
        VehicleCandidate(label: "test.toyota.corolla", make: "Toyota", model: "Corolla", generation: nil, score: 0.1),
    ]
    var delay: Duration = .zero

    var descriptor: IdentifierDescriptor {
        IdentifierDescriptor(providerID: Self.providerID, modelVersion: "test", labelMapVersion: "test")
    }

    var availability: IdentifierAvailability { .available }

    func identify(_ image: CGImage) async throws -> IdentificationOutcome {
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        return .available(candidates)
    }
}

/// Detection double with fixed boxes, so UI tests do not depend on Vision on the simulator.
struct FakeVehicleDetector: VehicleDetector {
    var boxes = [
        CropRect(x: 0.05, y: 0.3, width: 0.4, height: 0.4),
        CropRect(x: 0.55, y: 0.3, width: 0.4, height: 0.4),
    ]

    func detect(_ image: CGImage) async throws -> VehicleDetectionOutcome {
        .found(boxes)
    }
}

/// Segmentation double that never produces a mask.
struct UnavailableSegmenter: ForegroundSegmenter {
    func segment(_ image: CGImage) async throws -> SegmentationOutcome {
        .notUsable(.unsupported)
    }
}
#endif
