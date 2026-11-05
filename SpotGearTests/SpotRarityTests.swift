import Foundation
import SwiftData
import Testing
@testable import SpotGear

struct SpotRarityTests {
    @Test func priceBoundariesBelongToTheHigherTier() {
        let cases: [(Int?, SpotRarity)] = [
            (nil, .unknown), (0, .unknown), (-1, .unknown),
            (1, .common), (249_999, .common),
            (250_000, .uncommon), (749_999, .uncommon),
            (750_000, .rare), (1_999_999, .rare),
            (2_000_000, .epic), (4_999_999, .epic),
            (5_000_000, .legendary), (19_999_999, .legendary),
            (20_000_000, .mythic), (Int.max, .mythic)
        ]
        for (price, expected) in cases {
            #expect(SpotRarity(upperPriceCZK: price) == expected)
        }
    }

    @Test func fixedRewardsAndRepeatedSpots() {
        #expect(SpotRarity.allCases.map(\.xp) == [25, 25, 50, 100, 200, 400, 800])
        let facts = SpotFacts(make: "Test", xp: SpotRarity.epic.xp)
        #expect(GarageProgress(spots: Array(repeating: facts, count: 3)).xp == 600)
    }
}

@MainActor
struct RewardPersistenceTests {
    private let identity = VehicleIdentity(make: "Test", model: "Car", generation: "I")

    private func catalog(upper: Int) -> VehicleCatalog {
        VehicleCatalog(entries: [CatalogEntry(
            make: "Test", model: "Car", generation: "I", from: 2000, to: 2010,
            body: "coupe", powertrain: "petrol", powerKW: [100, 200], priceCZK: [100_000, upper]
        )])
    }

    private func insertLegacySpot(in container: ModelContainer) throws -> UUID {
        let spot = Spot(id: UUID(), createdAt: .now, observedAt: nil)
        spot.identityStatusRaw = IdentityStatus.userConfirmed.rawValue
        spot.make = identity.make
        spot.model = identity.model
        spot.generation = identity.generation
        container.mainContext.insert(spot)
        try container.mainContext.save()
        return spot.id
    }

    @Test func upperPriceIsSnapshottedAndSurvivesCatalogUpdatesAndReopening() throws {
        let storeURL = makeTemporaryDirectory().appendingPathComponent("Rewards.store")
        let id: UUID
        do {
            let container = try PersistenceController.makeContainer(storeURL: storeURL)
            id = try insertLegacySpot(in: container)
            _ = try SwiftDataSpotRepository(container: container, catalog: catalog(upper: 2_000_000))
            let spot = try #require(try container.mainContext.fetch(FetchDescriptor<Spot>()).first)
            #expect(spot.rewardPriceUpperCZK == 2_000_000)
            #expect(spot.rewardRarity == .epic)
            #expect(spot.facts.xp == 200)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: storeURL)
        let repository = try SwiftDataSpotRepository(container: reopened, catalog: catalog(upper: 20_000_000))
        let spot = try #require(try reopened.mainContext.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.id == id)
        #expect(spot.rewardPriceUpperCZK == 2_000_000)
        #expect(spot.rewardRarity == .epic)
        #expect(spot.facts.xp == 200)
        try repository.updateIdentity(spotID: id, identity: identity, source: .manual)
        #expect(spot.rewardPriceUpperCZK == 2_000_000)
        try repository.updateNote(spotID: id, note: "A note")
        try repository.setFavorite(spotID: id, isFavorite: true)
        #expect(spot.facts.xp == 200)
    }

    @Test func unknownRewardIsUpgradedWhenCatalogEntryBecomesAvailable() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        _ = try insertLegacySpot(in: container)
        _ = try SwiftDataSpotRepository(container: container, catalog: VehicleCatalog(entries: []))
        let spot = try #require(try container.mainContext.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.rewardRarity == .unknown)
        #expect(spot.facts.xp == 25)
        _ = try SwiftDataSpotRepository(container: container, catalog: catalog(upper: 750_000))
        #expect(spot.rewardRarity == .rare)
        #expect(spot.facts.xp == 100)
    }

    @Test func identityCorrectionRecalculatesRewardAndFailedSaveRollsBack() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let id = try insertLegacySpot(in: container)
        let repository = try SwiftDataSpotRepository(container: container, catalog: catalog(upper: 5_000_000))
        let spot = try #require(try container.mainContext.fetch(FetchDescriptor<Spot>()).first)
        repository.beforeSave = { throw CocoaError(.fileWriteOutOfSpace) }
        #expect(throws: CocoaError.self) {
            try repository.updateIdentity(spotID: id, identity: nil, source: .manual)
        }
        #expect(spot.rewardRarity == .legendary)
        #expect(spot.facts.xp == 400)
        #expect(spot.identity == identity)
        repository.beforeSave = nil
        try repository.updateIdentity(spotID: id, identity: nil, source: .manual)
        #expect(spot.rewardRarity == .unknown)
        #expect(spot.rewardPriceUpperCZK == nil)
        #expect(spot.facts.xp == 25)
        try repository.updateIdentity(spotID: id, identity: identity, source: .manual)
        #expect(spot.rewardRarity == .legendary)
        #expect(spot.facts.xp == 400)
    }

    @Test func v1StoreMigratesWithoutLosingCollectionOrPhotoRelationships() throws {
        let storeURL = makeTemporaryDirectory().appendingPathComponent("Migration.store")
        let id = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            context.autosaveEnabled = false
            let spot = SchemaV1.Spot(id: id, createdAt: .now, observedAt: nil)
            spot.identityStatusRaw = IdentityStatus.userConfirmed.rawValue
            spot.make = identity.make
            spot.model = identity.model
            spot.generation = identity.generation
            spot.note = "Original note"
            spot.isFavorite = true
            let asset = SchemaV1.PhotoAsset(id: UUID(), createdAt: .now, capturedAt: nil,
                                            relativePath: "source.jpg", width: 100, height: 80)
            let photo = SchemaV1.SpotPhoto(id: UUID(), order: 0, isPrimary: true, crop: .initial,
                                          revision: 0, cardStyle: .photo, renderVersion: 1,
                                          cutoutPath: nil, thumbnailPath: "thumb.jpg")
            context.insert(spot)
            context.insert(asset)
            context.insert(photo)
            photo.spot = spot
            photo.photoAsset = asset
            try context.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: storeURL)
        _ = try SwiftDataSpotRepository(container: migrated, catalog: catalog(upper: 750_000))
        let spot = try #require(try migrated.mainContext.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.id == id)
        #expect(spot.note == "Original note")
        #expect(spot.isFavorite)
        #expect(spot.identity == identity)
        #expect(spot.primaryPhoto?.thumbnailPath == "thumb.jpg")
        #expect(spot.primaryPhoto?.photoAsset?.relativePath == "source.jpg")
        #expect(spot.rewardRarity == .rare)
        #expect(spot.facts.xp == 100)
    }
}
