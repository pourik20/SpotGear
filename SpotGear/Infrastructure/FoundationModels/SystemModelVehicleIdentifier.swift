import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Suggests make/model from a crop with Apple's on-device system language model (iOS 27+, image input).
/// Never uses Private Cloud Compute or the network. On older systems, ineligible devices or while the
/// model is not ready it reports a concrete unavailability reason and produces no suggestions.
final class SystemModelVehicleIdentifier: VehicleIdentifier, @unchecked Sendable {
    static let providerID = "apple.system-language-model"

    let descriptor = IdentifierDescriptor(
        providerID: SystemModelVehicleIdentifier.providerID,
        modelVersion: "ios-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)",
        labelMapVersion: nil
    )

    var availability: IdentifierAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) { return Self.systemAvailability() }
        #endif
        return .unavailable(.systemUnsupported)
    }

    func identify(_ image: CGImage) async throws -> IdentificationOutcome {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            if case .unavailable(let reason) = Self.systemAvailability() { return .unavailable(reason) }
            return try await Self.suggest(for: image)
        }
        #endif
        return .unavailable(.systemUnsupported)
    }
}

#if canImport(FoundationModels)
@available(iOS 27.0, *)
extension SystemModelVehicleIdentifier {
    @Generable
    struct Response {
        @Guide(description: "True only if the main subject of the photo is a car, van or pickup truck.")
        var showsCar: Bool
        @Guide(
            description: "Up to three plausible identifications of the main car, most likely first. Empty when it is not a car or the make cannot be recognized.",
            .maximumCount(VehicleSuggestionRules.maximumCandidates)
        )
        var suggestions: [Suggestion]
    }

    @Generable
    struct Suggestion {
        @Guide(description: "Manufacturer brand exactly as the manufacturer writes it, e.g. Škoda, Mercedes-Benz, Volkswagen.")
        var make: String
        @Guide(description: "Model name, e.g. Octavia. Omit when unsure.")
        var model: String?
        @Guide(description: "Generation or body code only when clearly identifiable, e.g. III or W205. Omit otherwise.")
        var generation: String?
    }

    static let instructions = """
        You help a person catalogue cars they photographed for a private car-spotting collection. \
        Look only at the vehicle itself and suggest which make and model it is. \
        Prefer giving fewer suggestions over guessing. Never guess the production year. \
        Do not describe people, licence plates or locations.
        """

    static func systemAvailability() -> IdentifierAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.capabilities.contains(.vision) ? .available : .unavailable(.systemUnsupported)
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.systemUnsupported)
        }
    }

    static func suggest(for image: CGImage) async throws -> IdentificationOutcome {
        try Task.checkCancellation()
        // A fresh session per crop: no transcript is shared between regions or imports.
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(
                generating: Response.self,
                options: GenerationOptions(samplingMode: .greedy)
            ) {
                "Which car is shown in this photo?"
                Attachment(image)
            }
            try Task.checkCancellation()
            let content = response.content
            guard content.showsCar else { return .available([]) }
            let raw = content.suggestions.map {
                RawVehicleSuggestion(make: $0.make, model: $0.model, generation: $0.generation)
            }
            return .available(VehicleSuggestionRules.candidates(from: raw, labelPrefix: "system"))
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                // The model declined this image; that is "no suggestions", not a failure.
                return .available([])
            case .assetsUnavailable:
                return .unavailable(.modelNotReady)
            default:
                throw error
            }
        }
    }
}
#endif
