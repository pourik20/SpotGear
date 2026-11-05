import CoreGraphics
import Foundation
import Testing
@testable import SpotGear

struct CropRectTests {
    @Test func clampedKeepsCropInsideUnitSquare() {
        let crop = CropRect(x: 0.9, y: -0.2, width: 0.5, height: 0.01).clamped()
        #expect(crop.isValid)
        #expect(crop.x == 0.5)
        #expect(crop.y == 0)
        #expect(crop.height == CropRect.minimumSide)
    }

    @Test func nonFiniteValuesFallBackToValidCrop() {
        #expect(CropRect(x: .nan, y: .infinity, width: .nan, height: 0.3).clamped().isValid)
    }

    @Test func pixelRectIsIntegralAndNonEmpty() throws {
        let rect = try #require(CropRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25).pixelRect(imageWidth: 1001, imageHeight: 401))
        #expect(rect.minX == 250)
        #expect(rect.minY == 200)
        #expect(rect.maxX <= 1001)
        #expect(rect.maxY <= 401)
        #expect(CropRect.initial.pixelRect(imageWidth: 0, imageHeight: 10) == nil)
    }

    @Test func visionConversionFlipsTheYAxis() {
        let crop = CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let vision = crop.visionRect
        #expect(abs(vision.minY - 0.4) < 1e-9)
        let roundTrip = CropRect(visionRect: vision)
        #expect(abs(roundTrip.y - crop.y) < 1e-9)
        #expect(abs(roundTrip.height - crop.height) < 1e-9)
    }

    @Test func resizingKeepsCenterAndBounds() {
        let crop = CropRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2).resized(dWidth: 0.1, dHeight: 0)
        #expect(abs(crop.x - 0.35) < 1e-9)
        #expect(abs(crop.width - 0.3) < 1e-9)
        let large = CropRect(x: 0, y: 0, width: 1, height: 1).resized(dWidth: 0.5, dHeight: 0.5)
        #expect(large.isValid)
    }

    @Test func bottomRightResizeDoesNotLeaveImage() {
        let crop = CropRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2).resizedFromBottomRight(dx: 0.5, dy: 0.5)
        #expect(crop.x == 0.7)
        #expect(abs(crop.width - 0.3) < 1e-9)
        #expect(crop.isValid)
    }
}

struct ImageGeometryTests {
    @Test func aspectFitLetterboxesWideImageInTallContainer() {
        let fitted = ImageGeometry.aspectFitRect(imageSize: CGSize(width: 400, height: 200), in: CGSize(width: 200, height: 400))
        #expect(fitted == CGRect(x: 0, y: 150, width: 200, height: 100))
    }

    @Test func cropMapsIntoFittedRect() {
        let fitted = CGRect(x: 0, y: 150, width: 200, height: 100)
        let rect = ImageGeometry.viewRect(for: CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), in: fitted)
        #expect(rect == CGRect(x: 100, y: 200, width: 100, height: 50))
        let delta = ImageGeometry.normalizedDelta(CGSize(width: 20, height: 10), in: fitted)
        #expect(delta.dx == 0.1)
        #expect(delta.dy == 0.1)
    }

    @Test func exifOrientationsFiveToEightSwapAxes() {
        #expect(ImageGeometry.orientedSize(width: 400, height: 300, exifOrientation: 6) == CGSize(width: 300, height: 400))
        #expect(ImageGeometry.orientedSize(width: 400, height: 300, exifOrientation: 3) == CGSize(width: 400, height: 300))
    }
}

struct IdentityValidationTests {
    @Test func emptyMakeMeansUnknown() {
        #expect(IdentityValidation.validate(IdentityInput(make: "   ")) == .success(nil))
    }

    @Test func modelWithoutMakeIsRejected() {
        #expect(IdentityValidation.validate(IdentityInput(model: "Octavia")) == .failure(.modelWithoutMake))
    }

    @Test func valuesAreTrimmed() {
        let result = IdentityValidation.validate(IdentityInput(make: " Škoda ", model: " Octavia ", generation: " ", yearText: " 2015 "), currentYear: 2026)
        #expect(result == .success(VehicleIdentity(make: "Škoda", model: "Octavia", generation: nil, year: 2015)))
    }

    @Test(arguments: ["15", "20155", "abcd", "1700", "2099", "２０１５"])
    func invalidYearsAreRejected(_ year: String) {
        #expect(IdentityValidation.validate(IdentityInput(make: "Škoda", yearText: year), currentYear: 2026) == .failure(.invalidYear))
    }

    @Test func clearingMakeClearsDependentFields() {
        #expect(IdentityInput(make: "", model: "Golf", yearText: "2010").normalizedForMake() == IdentityInput())
    }
}

struct SearchTextTests {
    @Test func searchIgnoresCaseAndDiacritics() {
        #expect(SearchText.matches(query: "skoda", fields: ["Škoda", "Octavia"]))
        #expect(SearchText.matches(query: "ŠKODA oct", fields: ["Škoda", "Octavia"]))
        #expect(!SearchText.matches(query: "golf", fields: ["Škoda", "Octavia"]))
        #expect(SearchText.matches(query: "  ", fields: [nil]))
    }
}

struct RegionDraftTests {
    @Test func cropChangeInvalidatesSuggestionsAndConfirmationButKeepsText() {
        var region = RegionDraft(number: 1)
        region.input = IdentityInput(make: "Škoda")
        region.identification = .finished(.available([]))
        region.segmentation = .available(stagedFileName: "x.png")
        region.cardStyle = .cutout
        region.status = .confirmed
        region.confirmedIdentity = VehicleIdentity(make: "Škoda")

        region.updateCrop(CropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))

        #expect(region.revision == 1)
        #expect(region.status == .pending)
        #expect(region.confirmedIdentity == nil)
        #expect(region.identification == .notStarted)
        #expect(region.segmentation == .notStarted)
        #expect(region.cardStyle == .photo)
        #expect(region.input.make == "Škoda")
    }

    @Test func identicalCropDoesNotBumpRevision() {
        var region = RegionDraft(number: 1)
        region.updateCrop(region.crop)
        #expect(region.revision == 0)
    }
}

struct CandidatesSnapshotTests {
    @Test func snapshotIsVersionedAndRoundTrips() throws {
        let snapshot = CandidatesSnapshot(
            candidates: [VehicleCandidate(label: "a", make: "Škoda", model: nil, generation: nil, score: 0.5)],
            selectedLabel: "a",
            rejectedAll: false
        )
        let decoded = try CandidatesSnapshot.decode(try snapshot.encoded())
        #expect(decoded == snapshot)
        #expect(decoded.version == CandidatesSnapshot.currentVersion)
    }
}

struct VehicleSuggestionRulesTests {
    @Test func keepsOrderAndLimitsToThreeWithoutInventedScores() {
        let raw = ["Škoda", "Volkswagen", "Toyota", "Ford"].map { RawVehicleSuggestion(make: $0, model: "X") }
        let candidates = VehicleSuggestionRules.candidates(from: raw, labelPrefix: "t")
        #expect(candidates.map(\.make) == ["Škoda", "Volkswagen", "Toyota"])
        #expect(candidates.allSatisfy { $0.score == nil })
    }

    @Test func dropsEmptyMakesPlaceholdersAndDuplicates() {
        let raw = [
            RawVehicleSuggestion(make: "  ", model: "Octavia"),
            RawVehicleSuggestion(make: "Unknown", model: "Octavia"),
            RawVehicleSuggestion(make: " Škoda ", model: " Octavia ", generation: "III"),
            RawVehicleSuggestion(make: "skoda", model: "OCTAVIA", generation: "iii"),
            RawVehicleSuggestion(make: "Škoda", model: "n/a", generation: "III"),
        ]
        let candidates = VehicleSuggestionRules.candidates(from: raw, labelPrefix: "t")
        #expect(candidates.count == 2)
        #expect(candidates[0].identity == VehicleIdentity(make: "Škoda", model: "Octavia", generation: "III", year: nil))
        // A generation without a model would be rejected by the form, so it is dropped as well.
        #expect(candidates[1].identity == VehicleIdentity(make: "Škoda", model: nil, generation: nil, year: nil))
        #expect(Set(candidates.map(\.label)).count == candidates.count)
    }

    @Test func snapshotWithoutScoreRoundTripsAndOldPayloadStillDecodes() throws {
        let snapshot = CandidatesSnapshot(
            candidates: [VehicleCandidate(label: "t:a", make: "BMW", model: nil, generation: nil, score: nil)],
            selectedLabel: nil,
            rejectedAll: true
        )
        #expect(try CandidatesSnapshot.decode(snapshot.encoded()) == snapshot)
        let legacy = #"{"version":1,"candidates":[{"label":"a","make":"BMW","score":0.4}],"rejectedAll":false}"#
        #expect(try CandidatesSnapshot.decode(Data(legacy.utf8)).candidates.first?.score == 0.4)
    }
}

struct MediaPathTests {
    @Test(arguments: ["assets/a.jpg", "derived/b-thumb.jpg"])
    func acceptsKnownFolders(_ path: String) {
        #expect(MediaPaths.isSafe(path))
    }

    @Test(arguments: ["../x", "/etc/passwd", "assets/../x", "assets/", "staging/x", "assets/.hidden", "assets/a/b"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(!MediaPaths.isSafe(path))
    }
}

struct ForegroundInstancePickerTests {
    private func stats(_ label: Int, coverage: Double, distance: Double = 0) -> ForegroundInstanceStats {
        ForegroundInstanceStats(label: label, coverage: coverage, centerDistance: distance)
    }

    @Test func dominantCentralInstanceIsChosenOverSmallBystanders() {
        let pick = ForegroundInstancePicker.pick(
            [stats(1, coverage: 0.05, distance: 0.4), stats(2, coverage: 0.45, distance: 0.05), stats(3, coverage: 0.03, distance: 0.3)],
            minimumCoverage: 0.02
        )
        #expect(pick == .instance(label: 2))
    }

    @Test func comparableInstancesAreAmbiguous() {
        let pick = ForegroundInstancePicker.pick(
            [stats(1, coverage: 0.3, distance: 0.1), stats(2, coverage: 0.28, distance: 0.12)],
            minimumCoverage: 0.02
        )
        #expect(pick == .ambiguous)
    }

    @Test func tinyInstancesAreIgnored() {
        #expect(ForegroundInstancePicker.pick([stats(1, coverage: 0.01)], minimumCoverage: 0.02) == .noInstance)
        #expect(ForegroundInstancePicker.pick([], minimumCoverage: 0.02) == .noInstance)
        #expect(ForegroundInstancePicker.pick([stats(1, coverage: 0.4), stats(2, coverage: 0.01)], minimumCoverage: 0.02) == .instance(label: 1))
    }
}

struct ToneLevelsTests {
    private func histogram(_ bins: [Int: Int]) -> [Int] {
        var result = [Int](repeating: 0, count: 256)
        for (bin, count) in bins { result[bin] = count }
        return result
    }

    @Test func fullRangeImageIsLeftAlone() {
        #expect(ToneLevels(histogram: histogram([0: 500, 128: 5000, 255: 500])).isIdentity)
    }

    @Test func dullImageIsStretchedOnlyWithinLimits() {
        let levels = ToneLevels(histogram: histogram([40: 1000, 90: 4000, 150: 1000]))
        #expect(levels.blackPoint == ToneLevels.maximumBlackPoint)
        #expect(levels.whitePoint == ToneLevels.minimumWhitePoint)
        #expect(levels.scale <= 1 / (ToneLevels.minimumWhitePoint - ToneLevels.maximumBlackPoint) + 1e-9)
    }

    @Test func slightHazeIsRemovedExactly() {
        let levels = ToneLevels(histogram: histogram([5: 1000, 120: 4000, 250: 1000]))
        #expect(abs(levels.blackPoint - 5.0 / 255) < 1e-9)
        #expect(abs(levels.whitePoint - 250.0 / 255) < 1e-9)
    }

    @Test func tooFewPixelsMeanNoCorrection() {
        #expect(ToneLevels(histogram: histogram([60: 100])).isIdentity)
        #expect(ToneLevels(histogram: []).isIdentity)
    }
}
