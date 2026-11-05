/// Pixel statistics of one Vision foreground instance inside the user's crop.
struct ForegroundInstanceStats: Equatable, Sendable {
    var label: Int
    /// Share of the crop covered by the instance, 0...1.
    var coverage: Double
    /// Distance of the instance centroid from the crop center in crop-normalized units, 0...~0.71.
    var centerDistance: Double
}

/// Chooses the car the user framed: the large, central instance. Two comparable candidates stay ambiguous.
enum ForegroundInstancePicker {
    enum Pick: Equatable {
        case instance(label: Int)
        case noInstance
        case ambiguous
    }

    /// A runner-up scoring at least this share of the best one makes the choice ambiguous.
    static let ambiguityRatio = 0.6

    static func pick(_ instances: [ForegroundInstanceStats], minimumCoverage: Double) -> Pick {
        let ranked = instances
            .filter { $0.coverage >= minimumCoverage }
            .sorted { score($0) > score($1) }
        guard let best = ranked.first else { return .noInstance }
        if ranked.count > 1, score(ranked[1]) >= score(best) * ambiguityRatio { return .ambiguous }
        return .instance(label: best.label)
    }

    static func score(_ stats: ForegroundInstanceStats) -> Double {
        stats.coverage * max(0.2, 1 - stats.centerDistance * 1.2)
    }
}

/// Conservative black/white point correction. Applied equally to all channels, so hue stays;
/// it only removes a slight haze and lifts a dull exposure within tight limits, never re-lights the car.
struct ToneLevels: Equatable, Sendable {
    static let identity = ToneLevels(blackPoint: 0, whitePoint: 1)
    static let maximumBlackPoint = 0.05
    static let minimumWhitePoint = 0.85
    /// Fewer opaque pixels than this are not a reliable basis for a correction.
    static let minimumSampleCount = 256

    var blackPoint: Double
    var whitePoint: Double

    init(blackPoint: Double, whitePoint: Double) {
        self.blackPoint = blackPoint
        self.whitePoint = whitePoint
    }

    /// `histogram` holds 256 bins of encoded luminance of the opaque pixels.
    init(histogram: [Int]) {
        let total = histogram.reduce(0, +)
        guard histogram.count == 256, total >= Self.minimumSampleCount else {
            self = .identity
            return
        }
        let low = Self.percentile(0.005, of: histogram, total: total)
        let high = Self.percentile(0.995, of: histogram, total: total)
        let black = min(low, Self.maximumBlackPoint)
        let white = max(high, Self.minimumWhitePoint)
        // Changes below one 8-bit step are not worth a second pass over the image.
        self = black < 1 / 255 && white > 254 / 255 ? .identity : ToneLevels(blackPoint: black, whitePoint: white)
    }

    var isIdentity: Bool { self == .identity }
    var scale: Double { 1 / (whitePoint - blackPoint) }
    var bias: Double { -blackPoint * scale }

    private static func percentile(_ fraction: Double, of histogram: [Int], total: Int) -> Double {
        let target = Double(total) * fraction
        var cumulative = 0
        for (bin, count) in histogram.enumerated() {
            cumulative += count
            if Double(cumulative) > target { return Double(bin) / 255 }
        }
        return 1
    }
}
