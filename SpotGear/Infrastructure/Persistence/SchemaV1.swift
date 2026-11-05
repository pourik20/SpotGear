import Foundation
import SwiftData

/// Persisted schema V1. Released versions must not change; add `SchemaV2` and a migration stage instead.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PhotoAsset.self, Spot.self, SpotPhoto.self, IdentificationAttempt.self]
    }

    /// A normalized source photo, shared by every spot cut from it.
    @Model
    final class PhotoAsset {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var capturedAt: Date?
        var relativePath: String
        var width: Int
        var height: Int
        var contentHash: String?
        @Relationship(deleteRule: .nullify, inverse: \SpotPhoto.photoAsset)
        var spotPhotos: [SpotPhoto] = []

        init(id: UUID, createdAt: Date, capturedAt: Date?, relativePath: String, width: Int, height: Int, contentHash: String? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.capturedAt = capturedAt
            self.relativePath = relativePath
            self.width = width
            self.height = height
            self.contentHash = contentHash
        }
    }

    /// One observed car. Owns its photo links and identification attempts.
    @Model
    final class Spot {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var updatedAt: Date
        var observedAt: Date?
        var note: String
        var isFavorite: Bool
        var identityStatusRaw: String
        var make: String?
        var model: String?
        var generation: String?
        var year: Int?
        var identitySourceRaw: String?
        var confirmedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \SpotPhoto.spot)
        var photos: [SpotPhoto] = []
        @Relationship(deleteRule: .cascade, inverse: \IdentificationAttempt.spot)
        var attempts: [IdentificationAttempt] = []

        init(id: UUID, createdAt: Date, observedAt: Date?) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.observedAt = observedAt
            self.note = ""
            self.isFavorite = false
            self.identityStatusRaw = IdentityStatus.unknown.rawValue
        }
    }

    /// Link between a spot and a source photo with the crop and card derivatives.
    @Model
    final class SpotPhoto {
        @Attribute(.unique) var id: UUID
        var spot: Spot?
        var photoAsset: PhotoAsset?
        var order: Int
        var isPrimary: Bool
        var cropX: Double
        var cropY: Double
        var cropWidth: Double
        var cropHeight: Double
        var revision: Int
        var cardStyleRaw: String
        var renderVersion: Int
        var cutoutPath: String?
        var thumbnailPath: String?

        init(id: UUID, order: Int, isPrimary: Bool, crop: CropRect, revision: Int, cardStyle: CardStyle, renderVersion: Int, cutoutPath: String?, thumbnailPath: String?) {
            self.id = id
            self.order = order
            self.isPrimary = isPrimary
            self.cropX = crop.x
            self.cropY = crop.y
            self.cropWidth = crop.width
            self.cropHeight = crop.height
            self.revision = revision
            self.cardStyleRaw = cardStyle.rawValue
            self.renderVersion = renderVersion
            self.cutoutPath = cutoutPath
            self.thumbnailPath = thumbnailPath
        }
    }

    /// Provenance of suggestions shown for a spot. Never an identity by itself.
    @Model
    final class IdentificationAttempt {
        @Attribute(.unique) var id: UUID
        var spot: Spot?
        var createdAt: Date
        var inputRevision: Int
        var providerID: String
        var modelVersion: String?
        var labelMapVersion: String?
        var outcome: String
        var candidatesData: Data

        init(id: UUID, createdAt: Date, inputRevision: Int, providerID: String, modelVersion: String?, labelMapVersion: String?, outcome: String, candidatesData: Data) {
            self.id = id
            self.createdAt = createdAt
            self.inputRevision = inputRevision
            self.providerID = providerID
            self.modelVersion = modelVersion
            self.labelMapVersion = labelMapVersion
            self.outcome = outcome
            self.candidatesData = candidatesData
        }
    }
}

typealias PhotoAsset = SchemaV1.PhotoAsset
typealias Spot = SchemaV1.Spot
typealias SpotPhoto = SchemaV1.SpotPhoto
typealias IdentificationAttempt = SchemaV1.IdentificationAttempt

enum SpotGearMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
