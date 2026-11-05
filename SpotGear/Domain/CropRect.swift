import CoreGraphics

/// Normalized crop (0…1) with the origin in the top-left corner, relative to the
/// orientation-normalized source image.
struct CropRect: Equatable, Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let minimumSide = 0.05
    static let initial = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    private static let tolerance = 1e-9

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= -Self.tolerance && y >= -Self.tolerance
            && width >= Self.minimumSide - Self.tolerance
            && height >= Self.minimumSide - Self.tolerance
            && x + width <= 1 + Self.tolerance
            && y + height <= 1 + Self.tolerance
    }

    /// Returns a crop inside the unit square with at least the minimum side.
    func clamped() -> CropRect {
        func finite(_ value: Double, _ fallback: Double) -> Double { value.isFinite ? value : fallback }
        let w = min(max(finite(width, Self.initial.width), Self.minimumSide), 1)
        let h = min(max(finite(height, Self.initial.height), Self.minimumSide), 1)
        let cx = min(max(finite(x, 0), 0), 1 - w)
        let cy = min(max(finite(y, 0), 0), 1 - h)
        return CropRect(x: cx, y: cy, width: w, height: h)
    }

    func moved(dx: Double, dy: Double) -> CropRect {
        CropRect(x: x + dx, y: y + dy, width: width, height: height).clamped()
    }

    /// Changes the size around the current center; the result stays in bounds.
    func resized(dWidth: Double, dHeight: Double) -> CropRect {
        let w = min(max(width + dWidth, Self.minimumSide), 1)
        let h = min(max(height + dHeight, Self.minimumSide), 1)
        let centerX = x + width / 2
        let centerY = y + height / 2
        return CropRect(x: centerX - w / 2, y: centerY - h / 2, width: w, height: h).clamped()
    }

    /// Moves the bottom-right corner by a normalized delta, keeping the top-left corner fixed.
    func resizedFromBottomRight(dx: Double, dy: Double) -> CropRect {
        let w = min(max(width + dx, Self.minimumSide), 1 - x)
        let h = min(max(height + dy, Self.minimumSide), 1 - y)
        return CropRect(x: x, y: y, width: w, height: h).clamped()
    }

    /// Integral pixel rectangle inside the image; nil when the area would be empty.
    func pixelRect(imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let c = clamped()
        let w = Double(imageWidth)
        let h = Double(imageHeight)
        let minX = (c.x * w).rounded(.down)
        let minY = (c.y * h).rounded(.down)
        let maxX = min(((c.x + c.width) * w).rounded(.up), w)
        let maxY = min(((c.y + c.height) * h).rounded(.up), h)
        guard maxX - minX >= 1, maxY - minY >= 1 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Vision uses normalized coordinates with the origin in the bottom-left corner.
    var visionRect: CGRect {
        CGRect(x: x, y: 1 - y - height, width: width, height: height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(visionRect rect: CGRect) {
        self.init(x: rect.minX, y: 1 - rect.minY - rect.height, width: rect.width, height: rect.height)
    }
}

extension CropRect {
    /// Stable per crop, so a draft and its saved card get the same pixel scene.
    var sceneSeed: UInt64 {
        [x, y, width, height].reduce(UInt64(0)) { seed, value in
            seed &* 1_000_003 &+ UInt64(value * 10_000)
        }
    }
}
