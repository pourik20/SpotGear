import Foundation

extension SchemaV1.Spot {
    var identityStatus: IdentityStatus {
        IdentityStatus(rawValue: identityStatusRaw) ?? .unknown
    }

    var identitySource: IdentitySource? {
        identitySourceRaw.flatMap(IdentitySource.init(rawValue:))
    }

    var identity: VehicleIdentity? {
        guard identityStatus == .userConfirmed, let make else { return nil }
        return VehicleIdentity(make: make, model: model, generation: generation, year: year)
    }

    var primaryPhoto: SpotPhoto? {
        photos.first(where: \.isPrimary) ?? photos.min { $0.order < $1.order }
    }

    var displayTitle: String {
        identity?.title ?? String(localized: "Unknown Car")
    }

    /// Observation date when known, otherwise the date the spot was added.
    var displayDate: Date { observedAt ?? createdAt }

    var facts: SpotFacts {
        let identity = identity
        return SpotFacts(
            make: identity?.make,
            hasModel: identity?.model != nil,
            hasDetail: identity?.detail != nil,
            hasNote: !note.isEmpty,
            isFavorite: isFavorite
        )
    }

    func matches(search query: String) -> Bool {
        SearchText.matches(query: query, fields: [make, model, generation, year.map(String.init)])
    }
}

extension SchemaV1.SpotPhoto {
    var crop: CropRect {
        CropRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }

    var cardStyle: CardStyle {
        get { CardStyle(rawValue: cardStyleRaw) ?? .photo }
        set { cardStyleRaw = newValue.rawValue }
    }

    /// The style to render; a cutout without a file falls back to the photo crop.
    var effectiveCardStyle: CardStyle {
        cardStyle.resolved(hasCutout: cutoutPath != nil)
    }

    var imageRequest: CardImageRequest {
        CardImageRequest(
            sourcePath: photoAsset?.relativePath,
            thumbnailPath: thumbnailPath,
            cutoutPath: cutoutPath,
            crop: crop
        )
    }
}
