import Foundation

/// Persisted identity state. Suggestions are never an identity on their own.
enum IdentityStatus: String, Codable, Sendable {
    case unknown
    case userConfirmed
}

/// Origin of a user-confirmed identity.
enum IdentitySource: String, Codable, Sendable {
    case manual
    case modelSuggestion
}

/// A confirmed vehicle identity. An unknown car is represented by `nil`, not by an empty identity.
struct VehicleIdentity: Equatable, Sendable {
    var make: String
    var model: String?
    var generation: String?
    var year: Int?

    var title: String {
        [make, model].compactMap { $0 }.joined(separator: " ")
    }

    var detail: String? {
        let parts = [generation, year.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Raw text the user is editing. Kept as a draft even when a crop changes.
struct IdentityInput: Equatable, Sendable {
    var make = ""
    var model = ""
    var generation = ""
    var yearText = ""

    init(make: String = "", model: String = "", generation: String = "", yearText: String = "") {
        self.make = make
        self.model = model
        self.generation = generation
        self.yearText = yearText
    }

    init(identity: VehicleIdentity?) {
        self.init(
            make: identity?.make ?? "",
            model: identity?.model ?? "",
            generation: identity?.generation ?? "",
            yearText: identity?.year.map(String.init) ?? ""
        )
    }

    var hasMake: Bool { !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// An empty make means an unknown car, so dependent fields are cleared.
    func normalizedForMake() -> IdentityInput {
        hasMake ? self : IdentityInput(make: make)
    }
}

enum IdentityValidationError: Error, Equatable, Sendable {
    case modelWithoutMake
    case invalidYear
}

enum IdentityValidation {
    static let earliestYear = 1886

    /// Returns `nil` for an unknown car, otherwise a trimmed identity.
    static func validate(
        _ input: IdentityInput,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> Result<VehicleIdentity?, IdentityValidationError> {
        let make = trimmed(input.make)
        let model = trimmed(input.model)
        let generation = trimmed(input.generation)
        let yearText = trimmed(input.yearText)

        guard let make else {
            if model != nil || generation != nil || yearText != nil {
                return .failure(.modelWithoutMake)
            }
            return .success(nil)
        }

        var year: Int?
        if let yearText {
            guard yearText.count == 4,
                  yearText.allSatisfy(\.isASCII),
                  let value = Int(yearText),
                  (earliestYear...(currentYear + 1)).contains(value)
            else { return .failure(.invalidYear) }
            year = value
        }

        return .success(VehicleIdentity(make: make, model: model, generation: generation, year: year))
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
