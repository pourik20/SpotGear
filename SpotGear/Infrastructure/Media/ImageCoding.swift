import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO helpers: decoding with downsampling, orientation normalization and metadata-free encoding.
enum ImageCoding {
    struct NormalizedImage {
        var jpegData: Data
        var width: Int
        var height: Int
        var capturedAt: Date?
    }

    /// Decodes `data`, applies the EXIF orientation, downsamples to `maxPixelSize` and re-encodes
    /// a JPEG without the original metadata (GPS, device, EXIF). The capture date is returned separately.
    static func normalize(data: Data, maxPixelSize: Int) throws -> NormalizedImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) != nil
        else { throw MediaError.undecodable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let image = try orientedImage(from: source, maxPixelSize: maxPixelSize)
        return NormalizedImage(
            jpegData: try jpeg(image, quality: 0.9),
            width: image.width,
            height: image.height,
            capturedAt: properties.flatMap(captureDate(from:))
        )
    }

    /// Loads an already normalized file, downsampled so that the longer side is at most `maxPixelSize`.
    static func downsampledImage(at url: URL, maxPixelSize: Int) throws -> CGImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetCount(source) > 0
        else { throw MediaError.undecodable }
        return try orientedImage(from: source, maxPixelSize: maxPixelSize)
    }

    static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        try encode(image, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func png(_ image: CGImage) throws -> Data {
        try encode(image, type: .png, properties: [:])
    }

    private static func orientedImage(from source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0
        else { throw MediaError.undecodable }
        return image
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw MediaError.undecodable
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.undecodable }
        return data as Data
    }

    private static func captureDate(from properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String,
           let zone = TimeZone(identifier: "GMT\(offset.replacingOccurrences(of: ":", with: ""))") {
            formatter.timeZone = zone
        }
        return formatter.date(from: text)
    }
}
