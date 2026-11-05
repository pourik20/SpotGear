import Foundation
import SwiftData
import Testing
@testable import SpotGear

@MainActor
struct ImportSessionTests {
    @Test func threeRegionsSaveAsThreeSpotsWithOneSharedSource() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        #expect(session.phase == .selecting)

        for index in 0..<3 {
            let id = try #require(session.addRegion())
            session.updateCrop(CropRect(x: 0.05 + Double(index) * 0.32, y: 0.5, width: 0.26, height: 0.32), for: id)
        }
        session.proceedToReview()
        try await waitUntil { session.regions.allSatisfy { $0.status == .needsConfirmation } }

        session.updateInput(IdentityInput(make: "Škoda", model: "Octavia"), for: session.regions[0].id)
        for region in session.regions { #expect(session.confirm(region.id) == nil) }
        #expect(session.canSave)

        await session.save()

        #expect(session.phase == .completed)
        #expect(try harness.count(Spot.self) == 3)
        #expect(try harness.count(SpotPhoto.self) == 3)
        #expect(try harness.count(PhotoAsset.self) == 1)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("assets")) == 1)
        // Three thumbnails plus three cutouts from the stub segmenter.
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("derived")) == 6)
        #expect(!FileManager.default.fileExists(atPath: harness.stagingDirectory(session.id).path))
        #expect(try harness.repository.referencedMediaPaths().count == 7)
    }

    @Test func savingRequiresEveryRegionToBeConfirmed() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        let first = try #require(session.addRegion())
        session.addRegion()
        session.proceedToReview()
        session.confirm(first)
        #expect(!session.canSave)

        await session.save()
        #expect(session.phase == .reviewing)
        #expect(try harness.count(Spot.self) == 0)

        session.removeRegion(session.regions[1].id)
        #expect(session.canSave)
    }

    @Test func suggestionsAreNeverSavedWithoutConfirmation() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        let id = try #require(session.addRegion())
        session.proceedToReview()
        try await waitUntil { session.region(id)?.status == .needsConfirmation }
        #expect(session.region(id)?.identification.candidates.count == 2)

        session.chooseCandidate("a", for: id)
        #expect(session.region(id)?.status == .needsConfirmation)
        #expect(session.region(id)?.input.make == "Škoda")
        #expect(!session.canSave)

        session.rejectCandidates(for: id)
        session.markUnknown(id)
        session.confirm(id)
        await session.save()

        let spot = try #require(try harness.container.mainContext.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.identityStatus == .unknown)
        #expect(spot.make == nil)
        let attempt = try #require(spot.attempts.first)
        let snapshot = try CandidatesSnapshot.decode(attempt.candidatesData)
        #expect(snapshot.rejectedAll)
        #expect(snapshot.selectedLabel == nil)
        #expect(attempt.providerID == "test.stub")
    }

    @Test func confirmedSuggestionIsStoredWithModelSource() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        let id = try #require(session.addRegion())
        session.proceedToReview()
        try await waitUntil { session.region(id)?.status == .needsConfirmation }
        session.chooseCandidate("a", for: id)
        session.confirm(id)
        await session.save()

        let spot = try #require(try harness.container.mainContext.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.identity?.title == "Škoda Octavia")
        #expect(spot.identitySource == .modelSuggestion)
    }

    @Test func unavailableIdentifierProducesNoSuggestions() async throws {
        let harness = try Harness()
        let identifier = StubIdentifier(outcome: .unavailable(.modelMissing))
        let session = try await harness.loadedSession(identifier: identifier, segmenter: StubSegmenter(usable: false))
        let id = try #require(session.addRegion())
        session.proceedToReview()
        try await waitUntil { session.region(id)?.status == .needsConfirmation }
        #expect(session.identifierAvailability == .unavailable(.modelMissing))
        #expect(session.region(id)?.identification == .finished(.unavailable(.modelMissing)))
        #expect(session.region(id)?.segmentation == .notUsable(.ambiguous))

        session.confirm(id)
        await session.save()
        #expect(session.phase == .completed)
        let photo = try #require(try harness.container.mainContext.fetch(FetchDescriptor<SpotPhoto>()).first)
        #expect(photo.cutoutPath == nil)
        #expect(photo.cardStyle == .pixel)
    }

    @Test func staleResultIsIgnored() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        let id = try #require(session.addRegion())
        session.updateCrop(CropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), for: id)
        let region = try #require(session.region(id))

        session.apply(RegionProcessingResult(
            importID: session.id, regionID: id, revision: region.revision - 1,
            identification: .finished(.available([])), segmentation: .notUsable(.failed)
        ))
        #expect(session.region(id)?.identification == .notStarted)

        session.apply(RegionProcessingResult(
            importID: UUID(), regionID: id, revision: region.revision,
            identification: .finished(.available([])), segmentation: .notUsable(.failed)
        ))
        #expect(session.region(id)?.identification == .notStarted)
    }

    @Test func cropChangeDuringProcessingRequiresNewResultAndConfirmation() async throws {
        let harness = try Harness()
        let gate = Gate()
        let session = try await harness.loadedSession(identifier: StubIdentifier(gate: gate))
        let id = try #require(session.addRegion())
        session.focus(on: id)
        try await waitUntil { session.region(id)?.status == .processing }
        while await gate.waiterCount < 1 { try await Task.sleep(for: .milliseconds(10)) }

        session.updateCrop(CropRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3), for: id)
        #expect(session.region(id)?.revision == 1)
        #expect(session.region(id)?.status != .needsConfirmation)

        // Release the outdated call and the re-run for revision 1 (it may already be waiting).
        await gate.open()
        while await gate.waiterCount < 2 { try await Task.sleep(for: .milliseconds(10)) }
        await gate.open()
        try await waitUntil { session.region(id)?.status == .needsConfirmation }
        #expect(session.region(id)?.revision == 1)
        #expect(session.region(id)?.segmentation.stagedFileName?.contains("-r1-") == true)
    }

    @Test func cancelRemovesStagingAndSavesNothing() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        session.addRegion()
        #expect(FileManager.default.fileExists(atPath: harness.stagingDirectory(session.id).path))

        await session.cancel()

        #expect(session.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: harness.stagingDirectory(session.id).path))
        #expect(try harness.count(Spot.self) == 0)
    }

    @Test func doubleSaveCreatesOneBatch() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        let id = try #require(session.addRegion())
        session.proceedToReview()
        session.confirm(id)

        async let first: Void = session.save()
        async let second: Void = session.save()
        _ = await (first, second)

        #expect(try harness.count(Spot.self) == 1)
        #expect(try harness.count(PhotoAsset.self) == 1)
    }

    @Test func failedSaveKeepsCollectionAndCanBeRetried() async throws {
        let harness = try Harness()
        _ = try harness.repository.save(SpotBatch(
            importID: UUID(),
            asset: AssetRecord(id: UUID(), createdAt: Date(), capturedAt: nil, relativePath: "assets/existing.jpg", width: 1, height: 1),
            spots: [SpotRecord(spotID: UUID(), spotPhotoID: UUID(), createdAt: Date(), observedAt: nil, identity: nil, identitySource: nil, confirmedAt: nil, crop: .initial, revision: 0, cardStyle: .photo, thumbnailPath: "derived/existing.jpg", cutoutPath: nil, attempt: nil)]
        ))
        var failures = 1
        harness.repository.beforeSave = {
            if failures > 0 {
                failures -= 1
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }

        let session = try await harness.loadedSession(segmenter: StubSegmenter(usable: false))
        let id = try #require(session.addRegion())
        session.proceedToReview()
        session.confirm(id)

        await session.save()
        #expect(session.phase == .reviewing)
        #expect(session.saveError == .insufficientSpace)
        #expect(try harness.count(Spot.self) == 1)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("assets")) == 0)

        await session.save()
        #expect(session.phase == .completed)
        #expect(try harness.count(Spot.self) == 2)
        #expect(try harness.count(PhotoAsset.self) == 2)
    }

    @Test func corruptedFileReportsUnreadableImage() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession(data: FixtureImageFactory.corruptedData())
        #expect(session.loadError == .unreadableImage)
        #expect(session.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: harness.stagingDirectory(session.id).path))
    }

    @Test func lowDiskSpaceReportsInsufficientSpace() async throws {
        let harness = try Harness(availableCapacity: { _ in 10 })
        let session = try await harness.loadedSession()
        #expect(session.loadError == .insufficientSpace)
    }

    @Test func detectedCarsGoStraightToReviewWithTopSuggestionPrefilled() async throws {
        let harness = try Harness()
        let boxes = [
            CropRect(x: 0.55, y: 0.3, width: 0.3, height: 0.3),
            CropRect(x: 0.1, y: 0.3, width: 0.3, height: 0.3),
        ]
        let session = try await harness.loadedSession(detector: StubDetector(outcome: .found(boxes)))
        #expect(session.phase == .reviewing)
        #expect(session.regions.count == 2)
        #expect(session.regions[0].crop.x < session.regions[1].crop.x)

        try await waitUntil { session.regions.allSatisfy { $0.status == .needsConfirmation } }
        let first = session.regions[0]
        #expect(first.input.make == "Škoda")
        #expect(first.identitySource == .modelSuggestion)
        #expect(first.confirmedIdentity == nil)
        #expect(!session.canSave)

        for region in session.regions { session.confirm(region.id) }
        await session.save()
        #expect(session.phase == .completed)
        #expect(try harness.count(Spot.self) == 2)
    }

    @Test func noDetectedCarFallsBackToManualSelection() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        #expect(session.phase == .selecting)
        #expect(session.detection == .found([]))
        #expect(session.regions.isEmpty)
    }

    @Test func unavailableDetectorFallsBackToManualSelection() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession(detector: StubDetector(outcome: .unavailable))
        #expect(session.phase == .selecting)
        #expect(session.detection == .unavailable)
    }

    @Test func rejectingPrefilledSuggestionClearsItButKeepsTypedYear() async throws {
        let harness = try Harness()
        let boxes = [CropRect(x: 0.1, y: 0.3, width: 0.3, height: 0.3)]
        let session = try await harness.loadedSession(detector: StubDetector(outcome: .found(boxes)))
        let id = session.regions[0].id
        try await waitUntil { session.region(id)?.status == .needsConfirmation }

        var input = try #require(session.region(id)?.input)
        input.yearText = "2015"
        session.updateInput(input, for: id)
        session.rejectCandidates(for: id)

        #expect(session.region(id)?.input == IdentityInput(yearText: "2015"))
        #expect(session.region(id)?.identitySource == .manual)
    }

    @Test func regionLimitIsTen() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession()
        for _ in 0..<ImportSession.maximumRegions { session.addRegion() }
        #expect(session.addRegion() == nil)
        #expect(session.regions.count == 10)
    }

    @Test func libraryDeletionRemovesFilesOnlyWhenUnreferenced() async throws {
        let harness = try Harness()
        let session = try await harness.loadedSession(segmenter: StubSegmenter(usable: false))
        let a = try #require(session.addRegion())
        let b = try #require(session.addRegion())
        session.proceedToReview()
        session.confirm(a)
        session.confirm(b)
        await session.save()

        let library = SpotLibrary(repository: harness.repository, media: harness.media, cardImages: CardImageLoader(media: harness.media))
        try await library.deleteSpot(id: a)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("assets")) == 1)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("derived")) == 1)

        try await library.deleteSpot(id: b)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("assets")) == 0)
        #expect(fileCount(in: harness.mediaURL.appendingPathComponent("derived")) == 0)
    }
}
