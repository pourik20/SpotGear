import CoreGraphics
import CoreML
import Foundation
import Vision

/// Manifest bundled next to the optional `VehicleClassifier.mlmodelc`.
/// Supported contract: an image classifier with label → score output and a versioned label map.
struct ClassifierManifest: Codable, Equatable {
    static let supportedSchemaVersion = 1

    struct Label: Codable, Equatable {
        var make: String
        var model: String?
        var generation: String?
    }

    var schemaVersion: Int
    var modelVersion: String
    var labelMapVersion: String
    var license: String
    var labels: [String: Label]
}

enum IdentifierError: Error {
    case unexpectedOutput
}

/// Adapter for an optional bundled Core ML classifier. Without a valid model it reports unavailability
/// and never produces suggestions.
final class CoreMLVehicleIdentifier: VehicleIdentifier, @unchecked Sendable {
    static let providerID = "coreml.vehicle-classifier"
    static let defaultResourceName = "VehicleClassifier"
    static let maximumCandidates = 3

    let descriptor: IdentifierDescriptor
    let availability: IdentifierAvailability
    private let model: VNCoreMLModel?
    private let manifest: ClassifierManifest?

    init(bundle: Bundle = .main, resourceName: String = CoreMLVehicleIdentifier.defaultResourceName) {
        switch Self.load(bundle: bundle, resourceName: resourceName) {
        case .success(let (model, manifest)):
            self.model = model
            self.manifest = manifest
            availability = .available
            descriptor = IdentifierDescriptor(
                providerID: Self.providerID,
                modelVersion: manifest.modelVersion,
                labelMapVersion: manifest.labelMapVersion
            )
        case .failure(let reason):
            model = nil
            manifest = nil
            availability = .unavailable(reason)
            descriptor = IdentifierDescriptor(providerID: Self.providerID, modelVersion: nil, labelMapVersion: nil)
        }
    }

    func identify(_ image: CGImage) async throws -> IdentificationOutcome {
        guard let model, let manifest else {
            if case .unavailable(let reason) = availability { return .unavailable(reason) }
            return .unavailable(.modelMissing)
        }
        try Task.checkCancellation()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        guard let observations = request.results as? [VNClassificationObservation] else {
            throw IdentifierError.unexpectedOutput
        }

        let candidates = observations
            .sorted { $0.confidence > $1.confidence }
            .compactMap { observation -> VehicleCandidate? in
                guard observation.confidence > 0, let label = manifest.labels[observation.identifier] else { return nil }
                return VehicleCandidate(
                    label: observation.identifier,
                    make: label.make,
                    model: label.model,
                    generation: label.generation,
                    score: Double(observation.confidence)
                )
            }
            .prefix(Self.maximumCandidates)
        return .available(Array(candidates))
    }

    private static func load(
        bundle: Bundle,
        resourceName: String
    ) -> Result<(VNCoreMLModel, ClassifierManifest), IdentificationUnavailableReason> {
        guard let modelURL = bundle.url(forResource: resourceName, withExtension: "mlmodelc") else {
            return .failure(.modelMissing)
        }
        guard let manifestURL = bundle.url(forResource: "\(resourceName).manifest", withExtension: "json"),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ClassifierManifest.self, from: data),
              manifest.schemaVersion == ClassifierManifest.supportedSchemaVersion,
              !manifest.labels.isEmpty
        else { return .failure(.invalidManifest) }

        guard let mlModel = try? MLModel(contentsOf: modelURL) else { return .failure(.unsupportedModel) }
        let description = mlModel.modelDescription
        let hasImageInput = description.inputDescriptionsByName.values.contains { $0.type == .image }
        let hasScores = description.outputDescriptionsByName.values.contains { $0.type == .dictionary }
        let modelLabels = Set((description.classLabels ?? []).compactMap { $0 as? String })
        guard hasImageInput, hasScores, !modelLabels.isEmpty else { return .failure(.unsupportedModel) }
        guard Set(manifest.labels.keys).isSubset(of: modelLabels) else { return .failure(.invalidManifest) }
        guard let visionModel = try? VNCoreMLModel(for: mlModel) else { return .failure(.unsupportedModel) }
        return .success((visionModel, manifest))
    }
}
