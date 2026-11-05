import Foundation
import Testing
@testable import SpotGear

struct VehicleDetectionRulesTests {
    @Test func keepsDistinctCarsLeftToRight() {
        let right = CropRect(x: 0.6, y: 0.3, width: 0.3, height: 0.3)
        let left = CropRect(x: 0.1, y: 0.3, width: 0.2, height: 0.2)
        let regions = VehicleDetectionRules.regions(from: [right, left], limit: 10)
        #expect(regions.count == 2)
        #expect(regions[0].x < regions[1].x)
    }

    @Test func dropsTinyAndDuplicateBoxes() {
        let car = CropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let partOfCar = CropRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let tiny = CropRect(x: 0.8, y: 0.8, width: 0.06, height: 0.06)
        #expect(VehicleDetectionRules.regions(from: [partOfCar, tiny, car], limit: 10).count == 1)
    }

    @Test func keepsOverlappingNeighbours() {
        let first = CropRect(x: 0.1, y: 0.3, width: 0.4, height: 0.3)
        let second = CropRect(x: 0.4, y: 0.3, width: 0.4, height: 0.3)
        #expect(VehicleDetectionRules.regions(from: [first, second], limit: 10).count == 2)
    }

    @Test func limitKeepsTheLargestCars() {
        let boxes = (0..<4).map { CropRect(x: Double($0) * 0.24, y: 0, width: 0.1 + Double($0) * 0.04, height: 0.3) }
        let regions = VehicleDetectionRules.regions(from: boxes, limit: 2)
        #expect(regions.count == 2)
        #expect(regions.allSatisfy { $0.x > 0.4 })
    }

    @Test func marginStaysInsideTheImage() {
        let box = CropRect(x: 0, y: 0.9, width: 0.5, height: 0.1)
        let region = VehicleDetectionRules.regions(from: [box], limit: 10)[0]
        #expect(region.isValid)
        #expect(region.width > box.width)
    }
}

struct VehicleCatalogTests {
    private let catalog = VehicleCatalog(entries: [
        CatalogEntry(make: "Škoda", model: "Octavia", generation: "II", aliases: ["1Z"], from: 2004, to: 2013, body: "kombi", powertrain: "diesel", powerKW: [55, 147], priceCZK: [50_000, 190_000]),
        CatalogEntry(make: "Škoda", model: "Octavia", generation: "III", aliases: ["5E"], from: 2013, to: 2020, body: "kombi", powertrain: "diesel, CNG", powerKW: [63, 180], priceCZK: [130_000, 420_000]),
        CatalogEntry(make: "Tesla", model: "Model 3", generation: nil, aliases: nil, from: 2017, to: nil, body: "sedan", powertrain: "elektro", powerKW: [208, 393], priceCZK: [420_000, 1_400_000]),
        CatalogEntry(make: "Mercedes-Benz", model: "C", generation: "W205", aliases: nil, from: 2014, to: 2021, body: "sedan", powertrain: "benzin", powerKW: [115, 375], priceCZK: [320_000, 950_000]),
    ])

    private func identity(_ make: String, _ model: String?, generation: String? = nil, year: Int? = nil) -> VehicleIdentity {
        VehicleIdentity(make: make, model: model, generation: generation, year: year)
    }

    @Test func matchesRegardlessOfCaseAndDiacritics() {
        #expect(catalog.insight(for: identity("skoda", "OCTAVIA", generation: "iii"))?.generation == "III")
    }

    @Test func generationAliasAndYearNarrowTheResult() {
        #expect(catalog.insight(for: identity("Škoda", "Octavia", generation: "1Z"))?.priceCZK == 50_000...190_000)
        #expect(catalog.insight(for: identity("Škoda", "Octavia", year: 2008))?.generation == "II")
    }

    @Test func generationInModelNameCounts() {
        #expect(catalog.insight(for: identity("Škoda", "Octavia III Combi"))?.generation == "III")
    }

    @Test func unspecifiedGenerationSpansAllAndHidesDifferingData() throws {
        let insight = try #require(catalog.insight(for: identity("Škoda", "Octavia")))
        #expect(!insight.isGenerationSpecific)
        #expect(insight.priceCZK == 50_000...420_000)
        #expect(insight.yearFrom == 2004)
        #expect(insight.yearTo == 2020)
        #expect(insight.bodyStyle == "kombi")
        #expect(insight.powertrain == nil)
    }

    @Test func trimLevelInModelNameStillMatches() {
        #expect(catalog.insight(for: identity("Tesla", "Model 3 Performance"))?.yearTo == nil)
    }

    @Test func makeAliasesMatch() {
        #expect(catalog.insight(for: identity("Mercedes", "C"))?.generation == "W205")
    }

    @Test func modelNeedsWholeWordMatch() {
        #expect(catalog.insight(for: identity("Škoda", "Octavian")) == nil)
    }

    @Test func unknownCarOrMissingModelHasNoInsight() {
        #expect(catalog.insight(for: identity("Škoda", nil)) == nil)
        #expect(catalog.insight(for: identity("Gumpert", "Apollo")) == nil)
        #expect(catalog.insight(for: nil) == nil)
    }

    @Test func bundledCatalogLoadsWithConsistentData() throws {
        let url = try #require(Bundle.main.url(forResource: "VehicleCatalog", withExtension: "json"))
        let file = try JSONDecoder().decode(VehicleCatalogFile.self, from: Data(contentsOf: url))
        #expect(file.entries.count >= 100)
        for entry in file.entries {
            #expect(entry.priceCZK.count == 2 && entry.priceCZK[0] > 0 && entry.priceCZK[0] < entry.priceCZK[1], "\(entry.make) \(entry.model)")
            #expect(entry.powerKW.count == 2 && entry.powerKW[0] <= entry.powerKW[1], "\(entry.make) \(entry.model)")
            #expect(entry.from <= (entry.to ?? .max), "\(entry.make) \(entry.model)")
        }
        let bundled = VehicleCatalog.bundled()
        #expect(bundled.insight(for: VehicleIdentity(make: "Bugatti", model: "Chiron"))?.priceCZK.lowerBound ?? 0 > 10_000_000)
    }
}

struct VisionVehicleDetectorTests {
    /// The real detector on a real photo. Simulators without the Vision requests report `.unavailable`.
    @Test func findsTheCarInARealPhoto() async throws {
        let url = try #require(Bundle.main.url(forResource: "tesla", withExtension: "jpeg"))
        let image = try ImageCoding.downsampledImage(at: url, maxPixelSize: 2048)

        let outcome = try await VisionVehicleDetector().detect(image)

        guard case .found(let boxes) = outcome else { return }
        let regions = VehicleDetectionRules.regions(from: boxes, limit: 10)
        #expect(regions.count == 1)
        #expect(regions.first.map { $0.width > 0.8 && $0.y > 0.2 } == true)
    }
}
