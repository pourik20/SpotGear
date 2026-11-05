#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Test photos: the bundled `tesla.jpeg` and synthetic images drawn here. See TestFixtures/README.md.
enum FixtureImageFactory {
    /// The user-provided photo `tesla.jpeg`, bundled in Debug builds only (excluded from Release).
    static func bundledTestPhoto(in bundle: Bundle = .main) -> Data? {
        bundle.url(forResource: "tesla", withExtension: "jpeg").flatMap { try? Data(contentsOf: $0) }
    }

    /// A landscape scene with three simple car silhouettes, optionally stored with an EXIF orientation.
    static func threeCarsJPEG(width: Int = 1600, height: Int = 1000, exifOrientation: Int = 1) -> Data {
        let image = drawScene(width: width, height: height)
        return encode(image, orientation: exifOrientation, type: .jpeg)
    }

    /// An image whose four quadrants have distinct colors (TL red, TR green, BL blue, BR yellow),
    /// used to verify orientation handling. When stored with orientation 6 the raw pixels are rotated
    /// so that the decoded, oriented image matches the canonical layout.
    static func quadrantsJPEG(orientedWidth: Int = 400, orientedHeight: Int = 300, exifOrientation: Int = 1) -> Data {
        let canonical = drawQuadrants(width: orientedWidth, height: orientedHeight)
        guard exifOrientation == 6 else { return encode(canonical, orientation: 1, type: .jpeg) }
        // Orientation 6 means "rotate 90° clockwise to display": store the image rotated counter-clockwise.
        let stored = rotateCounterClockwise(canonical)
        return encode(stored, orientation: 6, type: .jpeg)
    }

    static func corruptedData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]) + Data(repeating: 0x42, count: 64)
    }

    // MARK: Drawing

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private static func drawScene(width: Int, height: Int) -> CGImage {
        let ctx = context(width: width, height: height)
        let w = CGFloat(width)
        let h = CGFloat(height)
        // Sky (top) and road (bottom). Core Graphics origin is bottom-left.
        ctx.setFillColor(CGColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.36, blue: 0.38, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.45))

        let colors = [
            CGColor(red: 0.80, green: 0.12, blue: 0.14, alpha: 1),
            CGColor(red: 0.10, green: 0.35, blue: 0.75, alpha: 1),
            CGColor(red: 0.95, green: 0.75, blue: 0.10, alpha: 1),
        ]
        for (index, color) in colors.enumerated() {
            let originX = w * (0.05 + CGFloat(index) * 0.32)
            drawCar(in: ctx, frame: CGRect(x: originX, y: h * 0.18, width: w * 0.26, height: h * 0.3), color: color)
        }
        return ctx.makeImage()!
    }

    private static func drawCar(in ctx: CGContext, frame: CGRect, color: CGColor) {
        ctx.setFillColor(color)
        let body = CGRect(x: frame.minX, y: frame.minY + frame.height * 0.2, width: frame.width, height: frame.height * 0.4)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: frame.height * 0.08, cornerHeight: frame.height * 0.08, transform: nil))
        ctx.fillPath()
        let cabin = CGRect(x: frame.minX + frame.width * 0.2, y: body.maxY, width: frame.width * 0.55, height: frame.height * 0.3)
        ctx.addPath(CGPath(roundedRect: cabin, cornerWidth: frame.height * 0.1, cornerHeight: frame.height * 0.1, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        let wheel = frame.height * 0.28
        for x in [frame.minX + frame.width * 0.12, frame.maxX - frame.width * 0.12 - wheel] {
            ctx.fillEllipse(in: CGRect(x: x, y: frame.minY + frame.height * 0.05, width: wheel, height: wheel))
        }
    }

    private static func drawQuadrants(width: Int, height: Int) -> CGImage {
        let ctx = context(width: width, height: height)
        let w = CGFloat(width) / 2
        let h = CGFloat(height) / 2
        // Core Graphics origin is bottom-left, so the visual top row is at y = h.
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: h, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: w, y: h, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: w, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private static func rotateCounterClockwise(_ image: CGImage) -> CGImage {
        let ctx = context(width: image.height, height: image.width)
        // Core Graphics is y-up, so a positive angle rotates counter-clockwise; then shift into view.
        ctx.translateBy(x: CGFloat(image.height), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()!
    }

    private static func encode(_ image: CGImage, orientation: Int, type: UTType) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:01 12:30:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.08, kCGImagePropertyGPSLatitudeRef: "N"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
#endif
