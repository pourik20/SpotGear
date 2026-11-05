import CoreGraphics
import Foundation

/// Procedural landscapes in the same low resolution as the pixel cards. A seed always gives the same
/// picture, so a card keeps its scene without storing an image.
enum PixelScene {
    enum Kind: CaseIterable, Sendable {
        case meadow
        case sunset
        case lilac
        case night

        init(seed: UInt64) {
            self = Self.allCases[Int(seed % UInt64(Self.allCases.count))]
        }

        fileprivate var palette: Palette {
            switch self {
            case .meadow:
                Palette(
                    sky: [0x2E6FBA, 0x4A9BDC, 0x7CC7EC, 0xBDE8F2], cloud: 0xF4FBFD, cloudShade: 0xB9DDEC,
                    far: 0x3F6B7E, farShade: 0x2F5163, snow: 0xE6F2F4,
                    hill: 0x2F7D5B, tree: 0x1C5A47, grass: 0x6FB552, grassShade: 0x4F9A4A,
                    road: 0x4A5568, roadEdge: 0x8592A6, flower: 0xF472B6, stars: false
                )
            case .sunset:
                Palette(
                    sky: [0x5B3A8C, 0xA8508F, 0xEE8A6D, 0xFBC77B], cloud: 0xFFD9B0, cloudShade: 0xE99A86,
                    far: 0x5D4579, farShade: 0x47345F, snow: 0xFBDCCB,
                    hill: 0x6A3B5E, tree: 0x3C2547, grass: 0xB5683C, grassShade: 0x8F4F3A,
                    road: 0x3F3247, roadEdge: 0xA5808F, flower: 0xFDE047, stars: false
                )
            case .lilac:
                Palette(
                    sky: [0x6D5BD0, 0x9F86E8, 0xD9A9EE, 0xFBD6E8], cloud: 0xFFF3FA, cloudShade: 0xE3BDEA,
                    far: 0x7464B8, farShade: 0x5B4C9B, snow: 0xF7ECFB,
                    hill: 0x4F7E9E, tree: 0x355D7C, grass: 0x7FCBA4, grassShade: 0x57AE8F,
                    road: 0x4B4A78, roadEdge: 0x9A97C8, flower: 0xFDE68A, stars: false
                )
            case .night:
                Palette(
                    sky: [0x0B1033, 0x1A1A5E, 0x34248F, 0x5B34B8], cloud: 0x4C3FA3, cloudShade: 0x352C80,
                    far: 0x241C66, farShade: 0x1A1450, snow: 0x8E86D9,
                    hill: 0x15205A, tree: 0x0D1540, grass: 0x1E3A6B, grassShade: 0x162C57,
                    road: 0x1B1B3F, roadEdge: 0x5B5FA8, flower: 0x7DD3FC, stars: true
                )
            }
        }
    }

    fileprivate struct Palette {
        var sky: [UInt32]
        var cloud: UInt32
        var cloudShade: UInt32
        var far: UInt32
        var farShade: UInt32
        var snow: UInt32
        var hill: UInt32
        var tree: UInt32
        var grass: UInt32
        var grassShade: UInt32
        var road: UInt32
        var roadEdge: UInt32
        var flower: UInt32
        var stars: Bool
    }

    private nonisolated(unsafe) static let cache = NSCache<NSString, CGImage>()

    static func image(_ kind: Kind, seed: UInt64, width: Int, height: Int, showsRoad: Bool = false) -> CGImage? {
        let key = "\(kind)-\(seed)-\(width)x\(height)-\(showsRoad)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = bitmap(kind, seed: seed, width: width, height: height, showsRoad: showsRoad)?.makeImage() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func bitmap(_ kind: Kind, seed: UInt64, width: Int, height: Int, showsRoad: Bool) -> PixelBitmap? {
        guard width > 0, height > 0 else { return nil }
        var painter = Painter(palette: kind.palette, seed: seed, width: width, height: height)
        painter.paintSky()
        painter.paintClouds()
        painter.paintMountains()
        painter.paintHills()
        painter.paintGround()
        if showsRoad { painter.paintRoad() }
        return painter.bitmap
    }

    /// Row where the ground begins, as a share of the height.
    private static let horizon = 0.62

    private struct Painter {
        let palette: Palette
        let width: Int
        let height: Int
        var random: SeededRandom
        var bitmap: PixelBitmap

        init(palette: Palette, seed: UInt64, width: Int, height: Int) {
            self.palette = palette
            self.width = width
            self.height = height
            random = SeededRandom(seed: seed)
            bitmap = PixelBitmap(width: width, height: height)
        }

        private var horizonY: Int { Int(Double(height) * PixelScene.horizon) }

        /// Bands of color blended with an ordered dither, the classic way to fake a gradient.
        mutating func paintSky() {
            let steps = palette.sky.count - 1
            for y in 0...horizonY {
                let position = Double(y) / Double(max(horizonY, 1)) * Double(steps)
                let band = min(Int(position), steps - 1)
                let blend = position - Double(band)
                for x in 0..<width {
                    let useNext = blend > Self.bayer[y % 4][x % 4]
                    bitmap.set(RGB(palette.sky[useNext ? band + 1 : band]), x: x, y: y)
                }
            }
            guard palette.stars else { return }
            for _ in 0..<(width * height / 90) {
                let x = random.int(below: width)
                let y = random.int(below: max(horizonY - 6, 1))
                bitmap.set(RGB(random.chance(0.25) ? 0xFDE68A : 0xE2E8F0), x: x, y: y)
            }
        }

        mutating func paintClouds() {
            for _ in 0..<max(width / 40, 3) {
                let centerX = random.int(below: width)
                let baseY = random.int(below: max(horizonY / 2, 1)) + height / 12
                let lobes = random.int(below: 3) + 3
                var x = centerX - lobes * 4
                for _ in 0..<lobes {
                    let radius = random.int(below: 3) + 3
                    fillDome(centerX: x, baseY: baseY, radius: radius)
                    x += radius + 2
                }
            }
        }

        private mutating func fillDome(centerX: Int, baseY: Int, radius: Int) {
            for dy in 0...radius {
                let halfWidth = Int((Double(radius * radius - dy * dy)).squareRoot() * 1.7)
                for x in (centerX - halfWidth)...(centerX + halfWidth) {
                    bitmap.set(RGB(dy == 0 ? palette.cloudShade : palette.cloud), x: x, y: baseY - dy)
                }
            }
        }

        mutating func paintMountains() {
            let peakCount = max(width / 40, 3)
            var ridge = [Int](repeating: horizonY, count: width)
            var lit = [Bool](repeating: false, count: width)
            for index in 0..<peakCount {
                let peakX = width * index / peakCount + random.int(below: max(width / peakCount, 1))
                let peakHeight = Double(height) * (0.2 + random.unit() * 0.2)
                let slope = 0.8 + random.unit() * 0.6
                for x in 0..<width {
                    let y = horizonY - Int(peakHeight - abs(Double(x - peakX)) * slope)
                    if y < ridge[x] {
                        ridge[x] = y
                        lit[x] = x <= peakX
                    }
                }
            }
            for x in 0..<width where ridge[x] < horizonY {
                let jitter = (x * 7 + x / 3) % 3
                let top = min(ridge[x] + jitter, horizonY)
                let snowLine = horizonY - Int(Double(height) * 0.27)
                for y in top...horizonY {
                    let isSnow = y < snowLine - (x % 5) / 2
                    let shade = lit[x] ? palette.far : palette.farShade
                    bitmap.set(RGB(isSnow ? palette.snow : shade), x: x, y: y)
                }
            }
        }

        mutating func paintHills() {
            let phase = random.unit() * 6
            var tops = [Int](repeating: 0, count: width)
            for x in 0..<width {
                let wave = sin(Double(x) * 0.045 + phase) + 0.5 * sin(Double(x) * 0.11 + phase * 2)
                tops[x] = horizonY - 4 - Int(wave * 3)
                for y in stride(from: tops[x], through: horizonY + 3, by: 1) {
                    bitmap.set(RGB(palette.hill), x: x, y: y)
                }
            }
            for _ in 0..<(width / 11) {
                let x = random.int(below: width)
                paintPine(x: x, baseY: tops[x] + 2, height: random.int(below: 6) + 9)
            }
        }

        private mutating func paintPine(x: Int, baseY: Int, height treeHeight: Int) {
            bitmap.set(RGB(palette.tree).scaled(by: 0.7), x: x, y: baseY)
            for row in 0..<treeHeight {
                let halfWidth = (treeHeight - row) / 3 + (row % 3 == 0 ? 0 : 1)
                for dx in -halfWidth...halfWidth {
                    bitmap.set(RGB(palette.tree), x: x + dx, y: baseY - row - 1)
                }
            }
        }

        mutating func paintGround() {
            let top = horizonY + 3
            guard top < height else { return }
            for y in top..<height {
                let depth = Double(y - top) / Double(max(height - top, 1))
                for x in 0..<width {
                    let useShade = depth > Self.bayer[y % 4][x % 4]
                    bitmap.set(RGB(useShade ? palette.grassShade : palette.grass), x: x, y: y)
                }
            }
            for _ in 0..<(width / 5) {
                let x = random.int(below: width)
                let y = top + 1 + random.int(below: max(height - top - 2, 1))
                bitmap.set(RGB(palette.flower), x: x, y: y)
                bitmap.set(RGB(palette.flower).scaled(by: 0.7), x: x + 1, y: y)
                bitmap.set(RGB(palette.grassShade).scaled(by: 0.8), x: x, y: y + 1)
            }
        }

        mutating func paintRoad() {
            let top = Int(Double(height) * 0.74)
            let bottom = Int(Double(height) * 0.93)
            guard top < bottom, bottom < height else { return }
            for y in top...bottom {
                let isEdge = y == top || y == bottom
                for x in 0..<width {
                    let isDash = y == (top + bottom) / 2 && x % 14 < 8
                    let color = isEdge || isDash ? palette.roadEdge : palette.road
                    bitmap.set(RGB(color), x: x, y: y)
                }
            }
            for _ in 0..<(width / 2) {
                let x = random.int(below: width)
                let y = top + 1 + random.int(below: max(bottom - top - 1, 1))
                bitmap.set(RGB(palette.road).scaled(by: 1.25), x: x, y: y)
            }
        }

        private static let bayer: [[Double]] = [
            [0.03, 0.53, 0.16, 0.66],
            [0.78, 0.28, 0.91, 0.41],
            [0.22, 0.72, 0.09, 0.59],
            [0.97, 0.47, 0.84, 0.34]
        ]
    }
}

/// SplitMix64: small, fast and identical on every run and device.
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(below limit: Int) -> Int {
        limit > 0 ? Int(next() % UInt64(limit)) : 0
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}
