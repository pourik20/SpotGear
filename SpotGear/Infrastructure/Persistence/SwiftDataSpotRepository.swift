import Foundation
import SwiftData

enum RepositoryError: Error, Equatable {
    case spotNotFound
    case cutoutUnavailable
    case invalidBatch
}

/// Owns the main `ModelContext` for writes. Autosave is off; every change is an explicit save
/// that is rolled back on failure.
@MainActor
final class SwiftDataSpotRepository: SpotRepository {
    let context: ModelContext
    /// Fault injection for tests and debug launch arguments; runs right before each save.
    var beforeSave: (() throws -> Void)?

    init(container: ModelContainer) {
        context = container.mainContext
        context.autosaveEnabled = false
    }

    func save(_ batch: SpotBatch) throws -> SaveOutcome {
        guard !batch.spots.isEmpty,
              MediaPaths.isSafe(batch.asset.relativePath),
              batch.spots.allSatisfy({ MediaPaths.isSafe($0.thumbnailPath) && ($0.cutoutPath.map(MediaPaths.isSafe) ?? true) })
        else { throw RepositoryError.invalidBatch }

        let assetID = batch.asset.id
        let existing = try context.fetchCount(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.id == assetID }))
        if existing > 0 { return .alreadySaved }

        let asset = PhotoAsset(
            id: batch.asset.id,
            createdAt: batch.asset.createdAt,
            capturedAt: batch.asset.capturedAt,
            relativePath: batch.asset.relativePath,
            width: batch.asset.width,
            height: batch.asset.height
        )
        context.insert(asset)

        for record in batch.spots {
            let spot = Spot(id: record.spotID, createdAt: record.createdAt, observedAt: record.observedAt)
            apply(identity: record.identity, source: record.identitySource, confirmedAt: record.confirmedAt, to: spot)
            context.insert(spot)

            let photo = SpotPhoto(
                id: record.spotPhotoID,
                order: 0,
                isPrimary: true,
                crop: record.crop,
                revision: record.revision,
                cardStyle: record.cardStyle.resolved(hasCutout: record.cutoutPath != nil),
                renderVersion: CardRenderer.renderVersion,
                cutoutPath: record.cutoutPath,
                thumbnailPath: record.thumbnailPath
            )
            context.insert(photo)
            photo.spot = spot
            photo.photoAsset = asset

            if let attempt = record.attempt {
                let stored = IdentificationAttempt(
                    id: attempt.id,
                    createdAt: attempt.createdAt,
                    inputRevision: attempt.inputRevision,
                    providerID: attempt.descriptor.providerID,
                    modelVersion: attempt.descriptor.modelVersion,
                    labelMapVersion: attempt.descriptor.labelMapVersion,
                    outcome: attempt.outcomeCode,
                    candidatesData: try attempt.snapshot.encoded()
                )
                context.insert(stored)
                stored.spot = spot
            }
        }

        try commit()
        return .saved
    }

    func updateIdentity(spotID: UUID, identity: VehicleIdentity?, source: IdentitySource) throws {
        let spot = try fetchSpot(spotID)
        apply(identity: identity, source: identity == nil ? nil : source, confirmedAt: Date(), to: spot)
        spot.updatedAt = Date()
        try commit()
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) throws {
        let spot = try fetchSpot(spotID)
        spot.isFavorite = isFavorite
        spot.updatedAt = Date()
        try commit()
    }

    func updateNote(spotID: UUID, note: String) throws {
        let spot = try fetchSpot(spotID)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spot.note != trimmed else { return }
        spot.note = trimmed
        spot.updatedAt = Date()
        try commit()
    }

    func setCardStyle(spotID: UUID, style: CardStyle) throws {
        let spot = try fetchSpot(spotID)
        guard let photo = spot.primaryPhoto else { throw RepositoryError.spotNotFound }
        if style == .cutout, photo.cutoutPath == nil { throw RepositoryError.cutoutUnavailable }
        photo.cardStyle = style
        spot.updatedAt = Date()
        try commit()
    }

    func deleteSpot(id: UUID) throws -> [String] {
        let spot = try fetchSpot(id)
        let deletedPhotoIDs = Set(spot.photos.map(\.id))
        var paths = spot.photos.flatMap { [$0.thumbnailPath, $0.cutoutPath].compactMap { $0 } }

        var assets: [UUID: PhotoAsset] = [:]
        for photo in spot.photos {
            if let asset = photo.photoAsset { assets[asset.id] = asset }
        }
        for asset in assets.values {
            let stillUsed = asset.spotPhotos.contains { !deletedPhotoIDs.contains($0.id) }
            if !stillUsed {
                paths.append(asset.relativePath)
                context.delete(asset)
            }
        }
        context.delete(spot)
        try commit()
        return paths
    }

    func deleteAll() throws -> [String] {
        let paths = Array(try referencedMediaPaths())
        for spot in try context.fetch(FetchDescriptor<Spot>()) { context.delete(spot) }
        for asset in try context.fetch(FetchDescriptor<PhotoAsset>()) { context.delete(asset) }
        try commit()
        return paths
    }

    func referencedMediaPaths() throws -> Set<String> {
        var paths = Set(try context.fetch(FetchDescriptor<PhotoAsset>()).map(\.relativePath))
        for photo in try context.fetch(FetchDescriptor<SpotPhoto>()) {
            if let path = photo.thumbnailPath { paths.insert(path) }
            if let path = photo.cutoutPath { paths.insert(path) }
        }
        return paths
    }

    // MARK: Helpers

    private func fetchSpot(_ id: UUID) throws -> Spot {
        var descriptor = FetchDescriptor<Spot>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let spot = try context.fetch(descriptor).first else { throw RepositoryError.spotNotFound }
        return spot
    }

    /// Unknown cars keep identity fields and `confirmedAt` empty.
    private func apply(identity: VehicleIdentity?, source: IdentitySource?, confirmedAt: Date?, to spot: Spot) {
        if let identity {
            spot.identityStatusRaw = IdentityStatus.userConfirmed.rawValue
            spot.make = identity.make
            spot.model = identity.model
            spot.generation = identity.generation
            spot.year = identity.year
            spot.identitySourceRaw = (source ?? .manual).rawValue
            spot.confirmedAt = confirmedAt
        } else {
            spot.identityStatusRaw = IdentityStatus.unknown.rawValue
            spot.make = nil
            spot.model = nil
            spot.generation = nil
            spot.year = nil
            spot.identitySourceRaw = nil
            spot.confirmedAt = nil
        }
    }

    private func commit() throws {
        do {
            try beforeSave?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
