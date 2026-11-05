import Foundation
import SwiftData
import Testing
@testable import SpotGear

/// Integration tests against a real on-disk SwiftData store.
@MainActor
struct RepositoryTests {
    private func batch(spots: Int, assetID: UUID = UUID()) -> SpotBatch {
        let now = Date()
        return SpotBatch(
            importID: UUID(),
            asset: AssetRecord(id: assetID, createdAt: now, capturedAt: nil, relativePath: MediaPaths.asset(assetID), width: 100, height: 80),
            spots: (0..<spots).map { index in
                let photoID = UUID()
                return SpotRecord(
                    spotID: UUID(),
                    spotPhotoID: photoID,
                    createdAt: now.addingTimeInterval(-Double(index)),
                    observedAt: nil,
                    identity: index == 0 ? VehicleIdentity(make: "Škoda", model: "Octavia") : nil,
                    identitySource: index == 0 ? .manual : nil,
                    confirmedAt: index == 0 ? now : nil,
                    crop: .initial,
                    revision: 0,
                    cardStyle: .photo,
                    thumbnailPath: MediaPaths.derived(MediaPaths.thumbnailName(spotPhotoID: photoID, revision: 0)),
                    cutoutPath: nil,
                    attempt: nil
                )
            }
        )
    }

    @Test func threeSpotsShareOneAssetAndSurviveReopen() throws {
        let root = makeTemporaryDirectory()
        let saved = batch(spots: 3)
        do {
            let harness = try Harness(root: root)
            #expect(try harness.repository.save(saved) == .saved)
            try harness.repository.setFavorite(spotID: saved.spots[1].spotID, isFavorite: true)
            try harness.repository.updateNote(spotID: saved.spots[2].spotID, note: "  U nádraží  ")
        }

        let reopened = try Harness(root: root)
        let spots = try reopened.container.mainContext.fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        #expect(spots.count == 3)
        #expect(try reopened.count(PhotoAsset.self) == 1)
        #expect(Set(spots.compactMap { $0.primaryPhoto?.photoAsset?.id }) == [saved.asset.id])
        #expect(spots[0].identity == VehicleIdentity(make: "Škoda", model: "Octavia"))
        #expect(spots[0].identitySource == .manual)
        #expect(spots[1].identityStatus == .unknown && spots[1].confirmedAt == nil && spots[1].make == nil)
        #expect(spots[1].isFavorite)
        #expect(spots[2].note == "U nádraží")
    }

    @Test func savingTheSameBatchTwiceCreatesNoDuplicates() throws {
        let harness = try Harness()
        let saved = batch(spots: 2)
        #expect(try harness.repository.save(saved) == .saved)
        #expect(try harness.repository.save(saved) == .alreadySaved)
        #expect(try harness.count(Spot.self) == 2)
        #expect(try harness.count(PhotoAsset.self) == 1)
    }

    @Test func failedSaveRollsBackTheWholeBatch() throws {
        let harness = try Harness()
        var shouldFail = true
        harness.repository.beforeSave = {
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        }
        let saved = batch(spots: 3)
        #expect(throws: CocoaError.self) { try harness.repository.save(saved) }
        #expect(try harness.count(Spot.self) == 0)
        #expect(try harness.count(PhotoAsset.self) == 0)
        #expect(try harness.count(SpotPhoto.self) == 0)

        shouldFail = false
        #expect(try harness.repository.save(saved) == .saved)
        #expect(try harness.count(Spot.self) == 3)
    }

    @Test func deletingOneOfThreeKeepsSharedAssetUntilTheLastOne() throws {
        let harness = try Harness()
        let saved = batch(spots: 3)
        _ = try harness.repository.save(saved)

        let first = try harness.repository.deleteSpot(id: saved.spots[0].spotID)
        #expect(first == [saved.spots[0].thumbnailPath])
        #expect(try harness.count(PhotoAsset.self) == 1)
        #expect(try harness.count(SpotPhoto.self) == 2)

        _ = try harness.repository.deleteSpot(id: saved.spots[1].spotID)
        let last = try harness.repository.deleteSpot(id: saved.spots[2].spotID)
        #expect(Set(last) == [saved.spots[2].thumbnailPath, saved.asset.relativePath])
        #expect(try harness.count(PhotoAsset.self) == 0)
        #expect(try harness.count(Spot.self) == 0)
    }

    @Test func identityCanBeCompletedAndClearedLater() throws {
        let harness = try Harness()
        let saved = batch(spots: 2)
        _ = try harness.repository.save(saved)
        let id = saved.spots[1].spotID

        try harness.repository.updateIdentity(spotID: id, identity: VehicleIdentity(make: "Tatra", model: "603"), source: .manual)
        let spot = try #require(try harness.container.mainContext.fetch(FetchDescriptor<Spot>(predicate: #Predicate { $0.id == id })).first)
        #expect(spot.identity?.title == "Tatra 603")
        #expect(spot.confirmedAt != nil)

        try harness.repository.updateIdentity(spotID: id, identity: nil, source: .manual)
        #expect(spot.identityStatus == .unknown)
        #expect(spot.confirmedAt == nil)
        #expect(spot.identitySource == nil)
    }

    @Test func cutoutStyleRequiresACutoutFile() throws {
        let harness = try Harness()
        let saved = batch(spots: 1)
        _ = try harness.repository.save(saved)
        #expect(throws: RepositoryError.cutoutUnavailable) {
            try harness.repository.setCardStyle(spotID: saved.spots[0].spotID, style: .cutout)
        }
    }

    @Test func deleteAllEmptiesTheStoreAndReturnsAllPaths() throws {
        let harness = try Harness()
        _ = try harness.repository.save(batch(spots: 2))
        _ = try harness.repository.save(batch(spots: 1))
        let paths = try harness.repository.deleteAll()
        #expect(paths.count == 5)
        #expect(try harness.count(Spot.self) == 0)
        #expect(try harness.count(PhotoAsset.self) == 0)
        #expect(try harness.repository.referencedMediaPaths().isEmpty)
    }

    @Test func invalidPathsAreRejectedBeforeWriting() throws {
        let harness = try Harness()
        var invalid = batch(spots: 1)
        invalid.asset.relativePath = "../escape.jpg"
        #expect(throws: RepositoryError.invalidBatch) { try harness.repository.save(invalid) }
        #expect(try harness.count(Spot.self) == 0)
    }
}
