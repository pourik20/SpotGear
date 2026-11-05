import CoreGraphics
import Testing
@testable import SpotGear

struct PixelArtTests {
    private func solidImage(width: Int, height: Int, inset: Int = 0) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset))
        return try #require(context.makeImage())
    }

    @Test func sameInputGivesSameScene() {
        let first = PixelScene.bitmap(.meadow, seed: 42, width: 80, height: 60, showsRoad: true)
        let second = PixelScene.bitmap(.meadow, seed: 42, width: 80, height: 60, showsRoad: true)
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func differentSeedsGiveDifferentScenes() {
        #expect(PixelScene.bitmap(.night, seed: 1, width: 80, height: 60, showsRoad: false)
            != PixelScene.bitmap(.night, seed: 2, width: 80, height: 60, showsRoad: false))
    }

    @Test func cardHasFixedPixelGrid() throws {
        let cutout = try solidImage(width: 600, height: 300)
        let card = try #require(PixelArt.card(cutout: cutout, seed: 3))
        #expect(card.width == PixelArt.cardWidth)
        #expect(card.height == PixelArt.cardHeight)
    }

    @Test func spriteTrimsMarginsAndAddsOutline() throws {
        let cutout = try solidImage(width: 400, height: 200, inset: 50)
        let sprite = try #require(PixelArt.carSprite(from: cutout))
        #expect(sprite.color(x: 0, y: sprite.height / 2) == PixelBitmap.outlineColor)
        #expect(sprite.alpha(x: 1, y: sprite.height / 2) == 255)
        #expect(sprite.alpha(x: 0, y: 0) == 0)
    }

    @Test func fullyTransparentCutoutGivesNoSprite() throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let empty = try #require(context.makeImage())
        #expect(PixelArt.carSprite(from: empty) == nil)
    }

    @Test func quantizeLimitsPalette() {
        var bitmap = PixelBitmap(width: 64, height: 64)
        for y in 0..<64 {
            for x in 0..<64 {
                bitmap.set(RGB(red: UInt8(x * 4), green: UInt8(y * 4), blue: UInt8((x + y) * 2)), x: x, y: y)
            }
        }
        bitmap.quantize(colors: 8)
        var colors = Set<RGB>()
        for y in 0..<64 {
            for x in 0..<64 { colors.insert(bitmap.color(x: x, y: y)) }
        }
        #expect(colors.count <= 8)
    }

    @Test func cardStyleFallsBackOnlyForMissingCutout() {
        #expect(CardStyle.cutout.resolved(hasCutout: false) == .photo)
        #expect(CardStyle.cutout.resolved(hasCutout: true) == .cutout)
        #expect(CardStyle.pixel.resolved(hasCutout: false) == .pixel)
    }
}

struct GarageProgressTests {
    @Test func emptyCollectionStartsAtLevelOne() {
        let progress = GarageProgress(spots: [])
        #expect(progress.level == 1)
        #expect(progress.xp == 0)
        #expect(progress.rank == .rookie)
        #expect(progress.completedQuestCount == 0)
    }

    @Test func xpDoesNotRewardFilledDetails() {
        #expect(SpotFacts().xp == 25)
        #expect(SpotFacts(make: "Škoda", hasModel: true, hasDetail: true, hasNote: true).xp == 25)
    }

    @Test func levelsConsumeXPAndKeepRemainder() {
        // 100 XP to level 2, another 150 to level 3; repeated Rare spots give full XP.
        let spots = Array(repeating: SpotFacts(make: "Tatra", hasModel: true, hasDetail: true, hasNote: true, xp: SpotRarity.rare.xp), count: 3)
            + Array(repeating: SpotFacts(), count: 1)
        let progress = GarageProgress(spots: spots)
        #expect(progress.xp == 325)
        #expect(progress.level == 3)
        #expect(progress.xpIntoLevel == 75)
        #expect(progress.xpForLevel == 200)
    }

    @Test func makesAreCountedIgnoringCaseAndDiacritics() {
        let progress = GarageProgress(spots: [SpotFacts(make: "Škoda"), SpotFacts(make: "skoda"), SpotFacts(make: "Tatra"), SpotFacts()])
        #expect(progress.makeCount == 2)
    }

    @Test func questProgressIsCappedAtGoal() {
        let progress = GarageProgress(spots: Array(repeating: SpotFacts(), count: 4))
        #expect(progress.progress(of: .firstSpot) == 1)
        #expect(progress.isCompleted(.firstSpot))
        #expect(progress.progress(of: .collector) == 4)
        #expect(!progress.isCompleted(.collector))
    }

    @Test func deletingSpotsLowersProgress() {
        let full = GarageProgress(spots: Array(repeating: SpotFacts(make: "Tatra"), count: 4))
        let reduced = GarageProgress(spots: [SpotFacts(make: "Tatra")])
        #expect(full.level > reduced.level)
    }
}
