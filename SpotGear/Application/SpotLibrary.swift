import Foundation

/// Use cases on the saved collection that touch both the database and files.
/// Metadata is saved first; files are removed only after the save succeeded.
@MainActor
final class SpotLibrary {
    private let repository: any SpotRepository
    private let media: any MediaStore
    private let cardImages: CardImageLoader

    init(repository: any SpotRepository, media: any MediaStore, cardImages: CardImageLoader) {
        self.repository = repository
        self.media = media
        self.cardImages = cardImages
    }

    func updateIdentity(spotID: UUID, input: IdentityInput, source: IdentitySource = .manual) throws -> IdentityValidationError? {
        switch IdentityValidation.validate(input) {
        case .failure(let error):
            return error
        case .success(let identity):
            try repository.updateIdentity(spotID: spotID, identity: identity, source: source)
            return nil
        }
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) throws {
        try repository.setFavorite(spotID: spotID, isFavorite: isFavorite)
    }

    func updateNote(spotID: UUID, note: String) throws {
        try repository.updateNote(spotID: spotID, note: note)
    }

    func setCardStyle(spotID: UUID, style: CardStyle) throws {
        try repository.setCardStyle(spotID: spotID, style: style)
    }

    func deleteSpot(id: UUID) async throws {
        let paths = try repository.deleteSpot(id: id)
        await media.deleteFiles(relativePaths: paths)
    }

    func deleteAll() async throws {
        _ = try repository.deleteAll()
        await media.deleteAllMedia()
        await cardImages.removeAll()
    }

    /// Recovery after an interrupted import or deletion: removes files nothing references.
    func sweepOrphanedMedia() async {
        guard let referenced = try? repository.referencedMediaPaths() else { return }
        await media.sweepOrphans(referencedPaths: referenced)
    }
}
