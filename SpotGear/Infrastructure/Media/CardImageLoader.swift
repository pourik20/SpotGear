import CoreGraphics
import Foundation

/// What a card or detail screen needs to show a stored spot photo.
struct CardImageRequest: Hashable, Sendable {
    var sourcePath: String?
    var thumbnailPath: String?
    var cutoutPath: String?
    var crop: CropRect
}

/// Loads library images off the main actor and regenerates a missing thumbnail from the source.
actor CardImageLoader {
    private let media: any MediaStore
    private let cache = NSCache<NSString, CGImage>()

    init(media: any MediaStore) {
        self.media = media
        cache.countLimit = 120
    }

    /// Nil means neither the thumbnail nor the source could be read.
    func thumbnail(for request: CardImageRequest) async -> CGImage? {
        if let path = request.thumbnailPath, let image = cachedImage(path: path, maxPixelSize: CardRenderer.thumbnailMaxPixelSize) {
            return image
        }
        guard let sourcePath = request.sourcePath,
              let sourceURL = media.url(forRelativePath: sourcePath),
              let source = try? ImageCoding.downsampledImage(at: sourceURL, maxPixelSize: FileMediaStore.sourceMaxPixelSize),
              let thumbnail = CardRenderer.thumbnail(from: source, crop: request.crop)
        else { return nil }

        if let path = request.thumbnailPath, let data = try? ImageCoding.jpeg(thumbnail, quality: 0.85) {
            try? await media.writeFile(data, relativePath: path)
            cache.setObject(thumbnail, forKey: path as NSString)
        }
        return thumbnail
    }

    func cutout(path: String) -> CGImage? {
        cachedImage(path: path, maxPixelSize: CardRenderer.thumbnailMaxPixelSize)
    }

    /// The pixel card is cheap to redraw, so it is only cached in memory and never written to disk.
    func pixelCard(for request: CardImageRequest) async -> CGImage? {
        let key = "pixel|\(request.cutoutPath ?? request.thumbnailPath ?? request.sourcePath ?? "")|\(request.crop.sceneSeed)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        var card: CGImage?
        if let path = request.cutoutPath, let cutout = cutout(path: path) {
            card = PixelArt.card(cutout: cutout, seed: request.crop.sceneSeed)
        }
        if card == nil, let thumbnail = await thumbnail(for: request) {
            card = PixelArt.card(photo: thumbnail)
        }
        if let card { cache.setObject(card, forKey: key) }
        return card
    }

    func source(path: String, maxPixelSize: Int) -> CGImage? {
        guard let url = media.url(forRelativePath: path) else { return nil }
        return try? ImageCoding.downsampledImage(at: url, maxPixelSize: maxPixelSize)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func cachedImage(path: String, maxPixelSize: Int) -> CGImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let url = media.url(forRelativePath: path),
              let image = try? ImageCoding.downsampledImage(at: url, maxPixelSize: maxPixelSize)
        else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
