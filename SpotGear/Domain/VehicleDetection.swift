import Foundation

/// Result of looking for cars in a whole photo. `found([])` means the detector ran and saw no car.
enum VehicleDetectionOutcome: Equatable, Sendable {
    case found([CropRect])
    case unavailable
}

enum VehicleDetectionRules {
    /// Smaller boxes are too far away for a usable card or identification.
    static let minimumArea = 0.01
    /// Share of the smaller box inside a larger one above which both are the same car.
    static let duplicateOverlap = 0.6
    /// Breathing room around the tight instance bounds, relative to the box size.
    static let margin = 0.04

    /// Keeps the largest distinct boxes up to `limit`, ordered left to right like the photo reads.
    static func regions(from boxes: [CropRect], limit: Int) -> [CropRect] {
        var kept: [CropRect] = []
        for box in boxes.sorted(by: { $0.area > $1.area }) where box.isValid && box.area >= minimumArea {
            guard kept.count < limit else { break }
            let isDuplicate = kept.contains { $0.overlapShare(of: box) > duplicateOverlap }
            if !isDuplicate { kept.append(box) }
        }
        return kept.map { $0.expanded(by: margin) }.sorted { $0.x < $1.x }
    }
}

extension CropRect {
    var area: Double { width * height }

    /// Share of `other` covered by this rectangle.
    func overlapShare(of other: CropRect) -> Double {
        let overlapWidth = min(x + width, other.x + other.width) - max(x, other.x)
        let overlapHeight = min(y + height, other.y + other.height) - max(y, other.y)
        guard overlapWidth > 0, overlapHeight > 0, other.area > 0 else { return 0 }
        return overlapWidth * overlapHeight / other.area
    }

    /// Grows the rectangle around its center by a share of its size, staying inside the image.
    func expanded(by share: Double) -> CropRect {
        let minX = max(x - width * share, 0)
        let minY = max(y - height * share, 0)
        let maxX = min(x + width * (1 + share), 1)
        let maxY = min(y + height * (1 + share), 1)
        return CropRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).clamped()
    }
}
