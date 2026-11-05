import CoreGraphics
import Foundation

// MARK: - Media

enum MediaError: Error, Equatable, Sendable {
    case undecodable
    case insufficientSpace
    case unsafePath
    case missingStagedFile
}

/// The normalized source written to an import's staging directory.
struct StagedSource: Equatable, Sendable {
    var importID: UUID
    var assetID: UUID
    var fileName: String
    var pixelWidth: Int
    var pixelHeight: Int
    var capturedAt: Date?
}

struct StagedFile: Equatable, Sendable {
    var stagingName: String
    var finalRelativePath: String
}

/// Files moved to their final location by one commit; used for rollback.
struct CommitReceipt: Equatable, Sendable {
    var importID: UUID
    var files: [StagedFile]
}

/// Relative media paths. Only paths produced here are ever read or deleted.
enum MediaPaths {
    static let assetsDirectory = "assets"
    static let derivedDirectory = "derived"

    static func asset(_ id: UUID) -> String { "\(assetsDirectory)/\(id.uuidString).jpg" }
    static func derived(_ fileName: String) -> String { "\(derivedDirectory)/\(fileName)" }

    static func thumbnailName(spotPhotoID: UUID, revision: Int) -> String {
        "\(spotPhotoID.uuidString)-r\(revision)-thumb.jpg"
    }

    static func cutoutName(spotPhotoID: UUID, revision: Int) -> String {
        "\(spotPhotoID.uuidString)-r\(revision)-cutout.png"
    }

    /// Accepts only `assets/<file>` or `derived/<file>` without traversal.
    static func isSafe(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              [assetsDirectory, derivedDirectory].contains(String(parts[0])) else { return false }
        let name = parts[1]
        return !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".")
    }
}

protocol MediaStore: Sendable {
    /// Decodes, orientation-normalizes and strips metadata, then writes the source to staging.
    func stageSource(_ data: Data, importID: UUID) async throws -> StagedSource
    func stageFile(_ data: Data, named fileName: String, importID: UUID) async throws
    func stagingURL(importID: UUID, fileName: String) -> URL
    /// Atomically moves staged files to their final location, or moves nothing.
    func commit(_ files: [StagedFile], importID: UUID) async throws -> CommitReceipt
    /// Moves committed files back to staging after a failed database save.
    func rollback(_ receipt: CommitReceipt) async
    /// Marks committed files as referenced by the database.
    func finishCommit(_ receipt: CommitReceipt) async
    func discardStaging(importID: UUID) async
    func url(forRelativePath path: String) -> URL?
    func writeFile(_ data: Data, relativePath: String) async throws
    func deleteFiles(relativePaths: [String]) async
    /// Removes inactive staging directories and media files that the database does not reference.
    func sweepOrphans(referencedPaths: Set<String>) async
    func deleteAllMedia() async
}

// MARK: - Local processing

protocol VehicleIdentifier: Sendable {
    var descriptor: IdentifierDescriptor { get }
    var availability: IdentifierAvailability { get }
    func identify(_ image: CGImage) async throws -> IdentificationOutcome
}

protocol VehicleDetector: Sendable {
    /// Cancellation is reported by throwing `CancellationError`.
    func detect(_ image: CGImage) async throws -> VehicleDetectionOutcome
}

protocol VehiclePriceClassifier: Sendable {
    /// Returns nil when no local model can answer. Never a concrete price.
    func classify(_ identity: VehicleIdentity) async throws -> VehiclePriceClass?
}

enum SegmentationOutcome: @unchecked Sendable {
    case cutout(CGImage)
    case notUsable(SegmentationFailure)
}

protocol ForegroundSegmenter: Sendable {
    /// Cancellation is reported by throwing `CancellationError` and is not a user-facing error.
    func segment(_ image: CGImage) async throws -> SegmentationOutcome
}

// MARK: - Persistence

struct AssetRecord: Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var capturedAt: Date?
    var relativePath: String
    var width: Int
    var height: Int
}

struct AttemptRecord: Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var inputRevision: Int
    var descriptor: IdentifierDescriptor
    var outcomeCode: String
    var snapshot: CandidatesSnapshot
}

struct SpotRecord: Equatable, Sendable {
    var spotID: UUID
    var spotPhotoID: UUID
    var createdAt: Date
    var observedAt: Date?
    var identity: VehicleIdentity?
    var identitySource: IdentitySource?
    var confirmedAt: Date?
    var crop: CropRect
    var revision: Int
    var cardStyle: CardStyle
    var thumbnailPath: String
    var cutoutPath: String?
    var attempt: AttemptRecord?
}

struct SpotBatch: Equatable, Sendable {
    var importID: UUID
    var asset: AssetRecord
    var spots: [SpotRecord]
}

enum SaveOutcome: Equatable, Sendable {
    case saved
    case alreadySaved
}

@MainActor
protocol SpotRepository: AnyObject {
    /// Saves the whole batch or nothing.
    func save(_ batch: SpotBatch) throws -> SaveOutcome
    func updateIdentity(spotID: UUID, identity: VehicleIdentity?, source: IdentitySource) throws
    func setFavorite(spotID: UUID, isFavorite: Bool) throws
    func updateNote(spotID: UUID, note: String) throws
    func setCardStyle(spotID: UUID, style: CardStyle) throws
    /// Returns media paths that are no longer referenced after the deletion was saved.
    func deleteSpot(id: UUID) throws -> [String]
    func deleteAll() throws -> [String]
    func referencedMediaPaths() throws -> Set<String>
}
