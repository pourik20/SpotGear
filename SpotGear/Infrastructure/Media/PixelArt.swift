import CoreGraphics
import Foundation

/// Turns a real photo or cutout into a pixel-art card by pure image processing: downscaling, a limited
/// palette and an outline. It is deterministic and works on every device, because the car's shape
/// and colors come from the user's own photo and nothing is invented by a generative model.
enum PixelArt {
    static let cardWidth = 160
    static let cardHeight = 120
    static let carColors = 20
    static let photoColors = 32

    /// Where the wheels touch the road, as a share of the card height.
    private static let floorLine = 0.86
    private static let maxCarWidth = 0.86
    private static let maxCarHeight = 0.62

    /// The cutout as a sprite parked on a generated scene, all on one pixel grid.
    static func card(cutout: CGImage, seed: UInt64) -> CGImage? {
        guard var scene = PixelScene.bitmap(
            PixelScene.Kind(seed: seed),
            seed: seed,
            width: cardWidth,
            height: cardHeight,
            showsRoad: true
        ), let sprite = carSprite(from: cutout) else { return nil }

        let floorY = Int(Double(cardHeight) * floorLine)
        let left = (cardWidth - sprite.width) / 2
        scene.darkenEllipse(
            centerX: cardWidth / 2,
            centerY: floorY - 1,
            radiusX: sprite.width / 2 + 1,
            radiusY: max(sprite.height / 12, 2)
        )
        scene.draw(sprite, x: left, y: floorY - sprite.height)
        return scene.makeImage()
    }

    /// Fallback without a usable cutout: the whole crop in a limited palette.
    static func card(photo: CGImage) -> CGImage? {
        guard var bitmap = PixelBitmap(aspectFilling: photo, width: cardWidth, height: cardHeight) else { return nil }
        bitmap.boostColors()
        bitmap.quantize(colors: photoColors)
        return bitmap.makeImage()
    }

    /// The car on a transparent background with a one-pixel outline around its silhouette.
    static func carSprite(from cutout: CGImage) -> PixelBitmap? {
        guard cutout.width > 0, cutout.height > 0 else { return nil }
        let aspect = Double(cutout.width) / Double(cutout.height)
        let maxWidth = Double(cardWidth) * maxCarWidth
        let maxHeight = Double(cardHeight) * maxCarHeight
        let width = max(Int(min(maxWidth, maxHeight * aspect).rounded()), 1)
        let height = max(Int((Double(width) / aspect).rounded()), 1)

        guard var bitmap = PixelBitmap(image: cutout, width: width, height: height) else { return nil }
        bitmap.hardenAlpha()
        guard var trimmed = bitmap.trimmedToOpaque() else { return nil }
        trimmed.boostColors()
        trimmed.quantize(colors: carColors)
        return trimmed.outlined()
    }
}

/// A straight-alpha RGBA buffer addressed from the top-left corner.
struct PixelBitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]

    static let outlineColor = RGB(0x0B1120)

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    init?(image: CGImage, width: Int, height: Int) {
        self.init(image: image, width: width, height: height, drawRect: CGRect(x: 0, y: 0, width: width, height: height))
    }

    init?(aspectFilling image: CGImage, width: Int, height: Int) {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale
        self.init(
            image: image,
            width: width,
            height: height,
            drawRect: CGRect(x: (Double(width) - drawWidth) / 2, y: (Double(height) - drawHeight) / 2, width: drawWidth, height: drawHeight)
        )
    }

    private init?(image: CGImage, width: Int, height: Int, drawRect: CGRect) {
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        self.init(width: width, height: height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            return true
        }
        guard drawn else { return nil }
        unpremultiply()
    }

    func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }

    func color(x: Int, y: Int) -> RGB {
        let index = (y * width + x) * 4
        return RGB(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2])
    }

    mutating func set(_ color: RGB, x: Int, y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let index = (y * width + x) * 4
        bytes[index] = color.red
        bytes[index + 1] = color.green
        bytes[index + 2] = color.blue
        bytes[index + 3] = 255
    }

    func makeImage() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Soft mask edges would turn into muddy pixels, so every pixel is either the car or background.
    mutating func hardenAlpha() {
        for index in stride(from: 3, to: bytes.count, by: 4) {
            bytes[index] = bytes[index] >= 128 ? 255 : 0
        }
    }

    /// Cuts away empty margins so the wheels really stand on the floor line.
    func trimmedToOpaque() -> PixelBitmap? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x: x, y: y) > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        var result = PixelBitmap(width: maxX - minX + 1, height: maxY - minY + 1)
        for y in minY...maxY {
            for x in minX...maxX where alpha(x: x, y: y) > 0 {
                result.set(color(x: x, y: y), x: x - minX, y: y - minY)
            }
        }
        return result
    }

    /// Pixel art reads better slightly more saturated and contrasty than a photo.
    mutating func boostColors(saturation: Double = 1.25, contrast: Double = 1.1) {
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = Double(bytes[index])
            let green = Double(bytes[index + 1])
            let blue = Double(bytes[index + 2])
            let luma = 0.299 * red + 0.587 * green + 0.114 * blue
            for (offset, value) in [red, green, blue].enumerated() {
                let saturated = luma + (value - luma) * saturation
                let adjusted = (saturated - 128) * contrast + 128
                bytes[index + offset] = UInt8(min(max(adjusted, 0), 255))
            }
        }
    }

    /// Median-cut palette reduction over the visible pixels.
    mutating func quantize(colors: Int) {
        let visible = (0..<(width * height)).filter { bytes[$0 * 4 + 3] > 0 }
        guard !visible.isEmpty, colors > 0 else { return }

        var boxes = [visible]
        while boxes.count < colors {
            let candidates = boxes.indices.filter { boxes[$0].count > 1 }
            guard let index = candidates.max(by: { longestSide(of: boxes[$0]).range < longestSide(of: boxes[$1]).range }),
                  longestSide(of: boxes[index]).range > 0
            else { break }
            let channel = longestSide(of: boxes[index]).channel
            let sorted = boxes[index].sorted { bytes[$0 * 4 + channel] < bytes[$1 * 4 + channel] }
            let middle = sorted.count / 2
            boxes[index] = Array(sorted[..<middle])
            boxes.append(Array(sorted[middle...]))
        }

        for box in boxes {
            var totals = [0, 0, 0]
            for pixel in box {
                for channel in 0..<3 { totals[channel] += Int(bytes[pixel * 4 + channel]) }
            }
            for pixel in box {
                for channel in 0..<3 { bytes[pixel * 4 + channel] = UInt8(totals[channel] / box.count) }
            }
        }
    }

    /// One pixel larger on each side, with a dark line around the silhouette.
    func outlined() -> PixelBitmap {
        var result = PixelBitmap(width: width + 2, height: height + 2)
        for y in 0..<height {
            for x in 0..<width where alpha(x: x, y: y) > 0 {
                result.set(color(x: x, y: y), x: x + 1, y: y + 1)
            }
        }
        let filled = result
        for y in 0..<result.height {
            for x in 0..<result.width where filled.alpha(x: x, y: y) == 0 {
                let touchesCar = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].contains { neighbor in
                    neighbor.0 >= 0 && neighbor.1 >= 0 && neighbor.0 < filled.width && neighbor.1 < filled.height
                        && filled.alpha(x: neighbor.0, y: neighbor.1) > 0
                }
                if touchesCar { result.set(Self.outlineColor, x: x, y: y) }
            }
        }
        return result
    }

    mutating func draw(_ sprite: PixelBitmap, x: Int, y: Int) {
        for spriteY in 0..<sprite.height {
            for spriteX in 0..<sprite.width where sprite.alpha(x: spriteX, y: spriteY) > 0 {
                set(sprite.color(x: spriteX, y: spriteY), x: x + spriteX, y: y + spriteY)
            }
        }
    }

    mutating func darkenEllipse(centerX: Int, centerY: Int, radiusX: Int, radiusY: Int) {
        guard radiusX > 0, radiusY > 0 else { return }
        for y in (centerY - radiusY)...(centerY + radiusY) where y >= 0 && y < height {
            for x in (centerX - radiusX)...(centerX + radiusX) where x >= 0 && x < width {
                let dx = Double(x - centerX) / Double(radiusX)
                let dy = Double(y - centerY) / Double(radiusY)
                if dx * dx + dy * dy <= 1 { set(color(x: x, y: y).scaled(by: 0.5), x: x, y: y) }
            }
        }
    }

    private func longestSide(of box: [Int]) -> (channel: Int, range: Int) {
        var best = (channel: 0, range: -1)
        for channel in 0..<3 {
            var low = 255, high = 0
            for pixel in box {
                let value = Int(bytes[pixel * 4 + channel])
                low = min(low, value)
                high = max(high, value)
            }
            if high - low > best.range { best = (channel, high - low) }
        }
        return best
    }

    private mutating func unpremultiply() {
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                bytes[index + channel] = UInt8(min(Int(bytes[index + channel]) * 255 / alpha, 255))
            }
        }
    }
}

struct RGB: Equatable, Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ hex: UInt32) {
        self.init(red: UInt8(hex >> 16 & 0xFF), green: UInt8(hex >> 8 & 0xFF), blue: UInt8(hex & 0xFF))
    }

    func scaled(by factor: Double) -> RGB {
        RGB(
            red: UInt8(min(Double(red) * factor, 255)),
            green: UInt8(min(Double(green) * factor, 255)),
            blue: UInt8(min(Double(blue) * factor, 255))
        )
    }
}
