import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SpotGear

struct ImageCodingTests {
    @Test func exifOrientationIsAppliedAndMetadataRemoved() throws {
        let data = FixtureImageFactory.quadrantsJPEG(exifOrientation: 6)
        let normalized = try ImageCoding.normalize(data: data, maxPixelSize: 4096)
        #expect(normalized.width == 400)
        #expect(normalized.height == 300)

        let image = try #require(decode(normalized.jpegData))
        let topLeft = pixel(of: image, x: 50, y: 50)
        let topRight = pixel(of: image, x: 350, y: 50)
        let bottomLeft = pixel(of: image, x: 50, y: 250)
        #expect(topLeft.r > 200 && topLeft.g < 60 && topLeft.b < 60)
        #expect(topRight.g > 200 && topRight.r < 60)
        #expect(bottomLeft.b > 200 && bottomLeft.r < 60)

        let source = try #require(CGImageSourceCreateWithData(normalized.jpegData as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        #expect(orientation == 1)
        #expect(normalized.capturedAt != nil)
    }

    @Test func cropAfterOrientationShowsTheExpectedQuadrant() throws {
        let normalized = try ImageCoding.normalize(data: FixtureImageFactory.quadrantsJPEG(exifOrientation: 6), maxPixelSize: 4096)
        let image = try #require(decode(normalized.jpegData))
        let crop = try #require(CardRenderer.crop(image, to: CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        let center = pixel(of: crop, x: crop.width / 2, y: crop.height / 2)
        #expect(center.r > 200 && center.g > 200 && center.b < 60) // yellow, bottom-right
    }

    @Test func largeImagesAreDownsampled() throws {
        let normalized = try ImageCoding.normalize(data: FixtureImageFactory.threeCarsJPEG(width: 3000, height: 2000), maxPixelSize: 1000)
        #expect(max(normalized.width, normalized.height) == 1000)
    }

    @Test func bundledTestPhotoNormalizes() throws {
        let data = try #require(FixtureImageFactory.bundledTestPhoto())
        let normalized = try ImageCoding.normalize(data: data, maxPixelSize: FileMediaStore.sourceMaxPixelSize)
        #expect(normalized.width == 768)
        #expect(normalized.height == 1024)
    }

    @Test func corruptedDataIsReportedAsUndecodable() {
        #expect(throws: MediaError.undecodable) {
            try ImageCoding.normalize(data: FixtureImageFactory.corruptedData(), maxPixelSize: 1000)
        }
    }
}

struct FileMediaStoreTests {
    @Test func commitMovesFilesAndRollbackRestoresThem() async throws {
        let root = makeTemporaryDirectory()
        let store = FileMediaStore(rootURL: root, availableCapacity: { _ in nil })
        let importID = UUID()
        try await store.stageFile(Data([1, 2, 3]), named: "a.jpg", importID: importID)

        let receipt = try await store.commit([StagedFile(stagingName: "a.jpg", finalRelativePath: "assets/a.jpg")], importID: importID)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/a.jpg").path))

        await store.rollback(receipt)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: store.stagingURL(importID: importID, fileName: "a.jpg").path))
    }

    @Test func failedCommitMovesNothing() async throws {
        let root = makeTemporaryDirectory()
        let store = FileMediaStore(rootURL: root, availableCapacity: { _ in nil })
        let importID = UUID()
        try await store.stageFile(Data([1]), named: "a.jpg", importID: importID)
        await #expect(throws: MediaError.missingStagedFile) {
            try await store.commit([
                StagedFile(stagingName: "a.jpg", finalRelativePath: "assets/a.jpg"),
                StagedFile(stagingName: "missing.jpg", finalRelativePath: "assets/b.jpg"),
            ], importID: importID)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/a.jpg").path))
    }

    @Test func unsafePathsAreRejected() async throws {
        let store = FileMediaStore(rootURL: makeTemporaryDirectory(), availableCapacity: { _ in nil })
        #expect(store.url(forRelativePath: "../outside") == nil)
        await #expect(throws: MediaError.unsafePath) {
            try await store.writeFile(Data(), relativePath: "assets/../../x")
        }
    }

    @Test func sweepRemovesOnlyUnreferencedFilesAndInactiveStaging() async throws {
        let root = makeTemporaryDirectory()
        let store = FileMediaStore(rootURL: root, availableCapacity: { _ in nil })
        for path in ["assets/keep.jpg", "assets/orphan.jpg", "derived/keep-thumb.jpg", "derived/orphan.png"] {
            try await store.writeFile(Data([0]), relativePath: path)
        }
        try await store.stageFile(Data([0]), named: "x.jpg", importID: UUID())

        await store.sweepOrphans(referencedPaths: ["assets/keep.jpg", "derived/keep-thumb.jpg"])

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("assets/keep.jpg").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("derived/keep-thumb.jpg").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("assets/orphan.jpg").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("derived/orphan.png").path))
        #expect(fileCount(in: root.appendingPathComponent("staging")) == 0)
    }

    @Test func insufficientSpaceIsReported() async throws {
        let store = FileMediaStore(rootURL: makeTemporaryDirectory(), availableCapacity: { _ in 1024 })
        await #expect(throws: MediaError.insufficientSpace) {
            try await store.stageSource(FixtureImageFactory.threeCarsJPEG(), importID: UUID())
        }
    }
}

@MainActor
struct CardImageLoaderTests {
    @Test func missingThumbnailIsRegeneratedFromSource() async throws {
        let root = makeTemporaryDirectory()
        let store = FileMediaStore(rootURL: root, availableCapacity: { _ in nil })
        let normalized = try ImageCoding.normalize(data: FixtureImageFactory.threeCarsJPEG(), maxPixelSize: 2048)
        try await store.writeFile(normalized.jpegData, relativePath: "assets/source.jpg")
        let loader = CardImageLoader(media: store)
        let request = CardImageRequest(sourcePath: "assets/source.jpg", thumbnailPath: "derived/t.jpg", cutoutPath: nil, crop: .initial)

        let image = await loader.thumbnail(for: request)

        #expect(image != nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("derived/t.jpg").path))
    }

    @Test func missingSourceAndThumbnailIsUnavailable() async {
        let loader = CardImageLoader(media: FileMediaStore(rootURL: makeTemporaryDirectory(), availableCapacity: { _ in nil }))
        let request = CardImageRequest(sourcePath: "assets/none.jpg", thumbnailPath: "derived/none.jpg", cutoutPath: nil, crop: .initial)
        #expect(await loader.thumbnail(for: request) == nil)
    }
}

struct CoreMLVehicleIdentifierTests {
    @Test func missingModelReportsUnavailableWithoutSuggestions() async throws {
        let identifier = CoreMLVehicleIdentifier(bundle: Bundle(for: BundleToken.self))
        #expect(identifier.availability == .unavailable(.modelMissing))
        let image = try #require(decode(FixtureImageFactory.threeCarsJPEG()))
        #expect(try await identifier.identify(image) == .unavailable(.modelMissing))
    }
}

struct SystemModelVehicleIdentifierTests {
    /// The live model cannot be asserted; only that its reported state and outcome agree.
    @Test func unavailableSystemModelProducesNoSuggestions() async throws {
        let identifier = SystemModelVehicleIdentifier()
        guard case .unavailable(let reason) = identifier.availability else { return }
        let image = try #require(decode(FixtureImageFactory.threeCarsJPEG()))
        #expect(try await identifier.identify(image) == .unavailable(reason))
    }

    @Test func testHostDoesNotUseTheSystemModel() {
        #expect(LaunchOptions.current.makeIdentifier().descriptor.providerID == CoreMLVehicleIdentifier.providerID)
    }
}

private final class BundleToken {}

struct CutoutEnhancerTests {
    /// Half-transparent canvas with an opaque, low-contrast grey block in the middle.
    private func dullCutout() throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.45, green: 0.30, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 50, y: 20, width: 100, height: 60))
        context.setFillColor(CGColor(red: 0.55, green: 0.40, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 50, y: 20, width: 50, height: 60))
        return try #require(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var data = [UInt8](repeating: 0, count: 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return data
    }

    @Test func keepsSizeTransparencyAndHueOrder() throws {
        let input = try dullCutout()
        let output = CutoutEnhancer.enhanced(input)
        #expect(output.width == input.width)
        #expect(output.height == input.height)

        #expect(try pixel(output, x: 5, y: 5)[3] == 0)
        let before = try pixel(input, x: 130, y: 50)
        let after = try pixel(output, x: 130, y: 50)
        #expect(after[3] == 255)
        // Same channel order (still a warm brown), slightly more contrast, no colour shift.
        #expect(after[0] > after[1] && after[1] > after[2])
        #expect(Int(after[0]) - Int(after[2]) >= Int(before[0]) - Int(before[2]))
    }

    @Test func histogramIgnoresTransparentPixels() throws {
        let histogram = CutoutEnhancer.luminanceHistogram(of: try dullCutout())
        #expect(histogram.reduce(0, +) == 100 * 60)
        #expect(histogram[0] == 0)
    }
}
