import Foundation

/// One generation of a car type in the bundled catalog. Prices are rough used-market ranges in CZK.
struct CatalogEntry: Codable, Equatable, Sendable {
    var make: String
    var model: String
    var generation: String?
    var aliases: [String]?
    var from: Int
    var to: Int?
    var body: String
    var powertrain: String
    var powerKW: [Int]
    var priceCZK: [Int]
}

struct VehicleCatalogFile: Codable, Sendable {
    var version: Int
    var priceDate: String
    var entries: [CatalogEntry]
}

/// What the catalog knows about a car type. Never used as a confirmed fact about the photographed car.
struct VehicleInsight: Equatable, Sendable {
    var generation: String?
    /// False when the identity fits several generations and the values span all of them.
    var isGenerationSpecific: Bool
    var yearFrom: Int
    var yearTo: Int?
    var bodyStyle: String?
    var powertrain: String?
    var powerKW: ClosedRange<Int>?
    var priceCZK: ClosedRange<Int>
}

/// Rough market class from the on-device model, offered only for cars outside the catalog.
enum VehiclePriceClass: String, CaseIterable, Sendable {
    case budget
    case mainstream
    case premium
    case luxury
    case supercar
    case collectible
}

/// Answers for the classifier when no local model can be used.
struct NoPriceClassifier: VehiclePriceClassifier {
    func classify(_ identity: VehicleIdentity) async throws -> VehiclePriceClass? { nil }
}

enum VehiclePriceFormat {
    static func range(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound.formatted()) – \(range.upperBound.formatted()) CZK"
    }
}

/// Offline lookup of prices and basic data. Deterministic on purpose: on-device model output for
/// prices and specifications was measurably unreliable, see ADR 0004.
struct VehicleCatalog: Sendable {
    let priceDate: String
    private let entriesByMake: [String: [CatalogEntry]]

    /// Common alternative spellings, in the normalized form of `normalized(_:)`.
    private static let makeAliases = ["vw": "volkswagen", "mercedes": "mercedes benz", "merc": "mercedes benz"]

    init(entries: [CatalogEntry], priceDate: String = "") {
        self.priceDate = priceDate
        entriesByMake = Dictionary(grouping: entries) { Self.normalized($0.make) }
    }

    func insight(for identity: VehicleIdentity?) -> VehicleInsight? {
        guard let identity, let identityModel = identity.model.map(Self.normalized) else { return nil }
        let make = Self.normalized(identity.make)
        let entries = entriesByMake[Self.makeAliases[make] ?? make] ?? []

        // "Octavia Combi" or "Model 3 Performance" still mean the catalog's Octavia or Model 3.
        let fitting = entries.filter { entry in
            let model = Self.normalized(entry.model)
            return identityModel == model || identityModel.hasPrefix(model + " ")
        }
        guard let longest = fitting.map({ Self.normalized($0.model).count }).max() else { return nil }
        let sameModel = fitting.filter { Self.normalized($0.model).count == longest }

        let chosen = Self.narrow(sameModel, identity: identity, identityModel: identityModel)
        return Self.merged(chosen)
    }

    /// Prefers the stated generation, then the stated year; otherwise keeps all generations.
    private static func narrow(_ entries: [CatalogEntry], identity: VehicleIdentity, identityModel: String) -> [CatalogEntry] {
        let hints = ([identity.generation.map(normalized)].compactMap { $0 })
            + identityModel.split(separator: " ").map(String.init)
        let byGeneration = entries.filter { entry in
            let names = ([entry.generation].compactMap { $0 } + (entry.aliases ?? [])).map(normalized)
            return names.contains { hints.contains($0) }
        }
        if !byGeneration.isEmpty { return byGeneration }
        if let year = identity.year {
            let byYear = entries.filter { $0.from <= year && year <= ($0.to ?? .max) }
            if !byYear.isEmpty { return byYear }
        }
        return entries
    }

    private static func merged(_ entries: [CatalogEntry]) -> VehicleInsight? {
        guard let first = entries.first else { return nil }
        let isSpecific = entries.count == 1
        return VehicleInsight(
            generation: isSpecific ? first.generation : nil,
            isGenerationSpecific: isSpecific,
            yearFrom: entries.map(\.from).min() ?? first.from,
            yearTo: entries.contains { $0.to == nil } ? nil : entries.compactMap(\.to).max(),
            bodyStyle: Set(entries.map(\.body)).count == 1 ? first.body : nil,
            powertrain: Set(entries.map(\.powertrain)).count == 1 ? first.powertrain : nil,
            powerKW: span(entries.flatMap(\.powerKW)),
            priceCZK: span(entries.flatMap(\.priceCZK)) ?? 0...0
        )
    }

    private static func span(_ values: [Int]) -> ClosedRange<Int>? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }

    private static func normalized(_ text: String) -> String {
        SearchText.fold(text)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension VehicleCatalog {
    /// An unreadable catalog only hides the info panel; it must never block importing.
    static func bundled(in bundle: Bundle = .main) -> VehicleCatalog {
        guard let url = bundle.url(forResource: "VehicleCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(VehicleCatalogFile.self, from: data)
        else { return VehicleCatalog(entries: []) }
        return VehicleCatalog(entries: file.entries, priceDate: file.priceDate)
    }
}
