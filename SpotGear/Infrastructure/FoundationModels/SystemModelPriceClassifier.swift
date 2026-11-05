import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks the on-device system model for a coarse market class. It deliberately never asks for a price:
/// the same model invented numbers for rare cars, while the class stayed plausible (ADR 0004).
struct SystemModelPriceClassifier: VehiclePriceClassifier {
    func classify(_ identity: VehicleIdentity) async throws -> VehiclePriceClass? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return try await Self.answer(for: identity)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension SystemModelPriceClassifier {
    @Generable
    enum Tier: String {
        case budget, mainstream, premium, luxury, supercar, collectible
    }

    @Generable
    struct Response {
        var tier: Tier
    }

    static func answer(for identity: VehicleIdentity) async throws -> VehiclePriceClass? {
        let session = LanguageModelSession(model: .default, instructions: "You are a car expert.")
        do {
            let response = try await session.respond(
                generating: Response.self,
                options: GenerationOptions(samplingMode: .greedy)
            ) {
                "Which market tier is the \(identity.title)?"
            }
            return VehiclePriceClass(rawValue: response.content.tier.rawValue)
        } catch is LanguageModelSession.GenerationError {
            // No class is a valid answer; the panel just stays without it.
            return nil
        }
    }
}
#endif
