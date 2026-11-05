import CoreGraphics

/// Pure rendering of card derivatives from the normalized source. Never generates missing content.
enum CardRenderer {
    static let renderVersion = 1
    static let thumbnailMaxPixelSize = 1200

    static func crop(_ image: CGImage, to crop: CropRect) -> CGImage? {
        guard let rect = crop.pixelRect(imageWidth: image.width, imageHeight: image.height) else { return nil }
        return image.cropping(to: rect)
    }

    static func thumbnail(from source: CGImage, crop: CropRect) -> CGImage? {
        self.crop(source, to: crop).map { scaled($0, maxPixelSize: thumbnailMaxPixelSize) }
    }

    /// Downscales proportionally; images that already fit are returned unchanged.
    static func scaled(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize, maxPixelSize > 0 else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
