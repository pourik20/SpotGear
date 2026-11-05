import Foundation

/// A suggestion from a local model. The score, when the provider has one, is kept for provenance
/// and ordering only; the UI never shows it as a confidence percentage.
struct VehicleCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { label }
    var label: String
    var make: String
    var model: String?
    var generation: String?
    var score: Double?

    var identity: VehicleIdentity {
        VehicleIdentity(make: make, model: model, generation: generation, year: nil)
    }
}

enum IdentificationUnavailableReason: String, Codable, Equatable, Sendable, Error {
    case modelMissing
    case invalidManifest
    case unsupportedModel
    /// The OS has no on-device system model with image input.
    case systemUnsupported
    case deviceNotEligible
    case appleIntelligenceDisabled
    /// The system model is still downloading or otherwise not ready yet.
    case modelNotReady
}

enum IdentificationOutcome: Equatable, Sendable {
    case available([VehicleCandidate])
    case unavailable(IdentificationUnavailableReason)

    var storageCode: String {
        switch self {
        case .available: "available"
        case .unavailable(let reason): "unavailable.\(reason.rawValue)"
        }
    }
}

enum IdentifierAvailability: Equatable, Sendable {
    case available
    case unavailable(IdentificationUnavailableReason)
}

/// Identifies the provider of suggestions for stored attempts.
struct IdentifierDescriptor: Equatable, Sendable {
    var providerID: String
    var modelVersion: String?
    var labelMapVersion: String?
}

/// Versioned snapshot of candidates stored with an identification attempt.
struct CandidatesSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = CandidatesSnapshot.currentVersion
    var candidates: [VehicleCandidate]
    var selectedLabel: String?
    var rejectedAll: Bool

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> CandidatesSnapshot {
        try JSONDecoder().decode(CandidatesSnapshot.self, from: data)
    }
}

/// One raw suggestion from a generative model before validation.
struct RawVehicleSuggestion: Equatable, Sendable {
    var make: String
    var model: String?
    var generation: String?
}

enum VehicleSuggestionRules {
    static let maximumCandidates = 3

    /// Turns free-form model output into at most three distinct candidates. Empty makes are dropped,
    /// blank optional fields become nil and duplicates (ignoring case and diacritics) are merged.
    /// Order is kept as the provider's ranking; no score is invented.
    static func candidates(from raw: [RawVehicleSuggestion], labelPrefix: String) -> [VehicleCandidate] {
        var seen: Set<String> = []
        var result: [VehicleCandidate] = []
        for suggestion in raw {
            guard let make = cleaned(suggestion.make) else { continue }
            let model = cleaned(suggestion.model)
            let generation = model == nil ? nil : cleaned(suggestion.generation)
            let key = [make, model, generation].map { SearchText.fold($0 ?? "") }.joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            result.append(VehicleCandidate(
                label: "\(labelPrefix):\(key)", make: make, model: model, generation: generation, score: nil
            ))
            if result.count == maximumCandidates { break }
        }
        return result
    }

    /// Folded forms of answers that mean "no value".
    private static let placeholders: Set<String> = ["unknown", "n/a", "none", "null", "-", "?", "nevim", "nezname"]

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !placeholders.contains(SearchText.fold(trimmed)) else { return nil }
        return trimmed
    }
}
