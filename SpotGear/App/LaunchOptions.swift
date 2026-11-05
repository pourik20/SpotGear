import Foundation

/// Launch configuration. Test providers and fixtures exist only in DEBUG builds.
struct LaunchOptions {
    var isolatedDataDirectory: URL?
    var resetsIsolatedData = false
    var usesFakeIdentifier = false
    var usesFakeDetector = false
    /// UI tests and the unit test host run without the system model so results stay deterministic.
    var usesSystemModel = true
    var failsFirstSave = false
    var offersTestPhotos = false

    static var current: LaunchOptions {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITest = arguments.contains("-ui-testing")
        var options = LaunchOptions()
        options.offersTestPhotos = true
        if isUITest || isUnitTestHost {
            options.isolatedDataDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(isUITest ? "SpotGearUITestData" : "SpotGearTestHostData", isDirectory: true)
            options.resetsIsolatedData = isUnitTestHost || arguments.contains("-ui-reset")
            options.usesSystemModel = false
        }
        options.usesFakeIdentifier = arguments.contains("-ui-fake-identifier")
        options.usesFakeDetector = arguments.contains("-ui-fake-detector")
        options.failsFirstSave = arguments.contains("-ui-fail-first-save")
        return options
        #else
        return LaunchOptions()
        #endif
    }

    func makeIdentifier() -> any VehicleIdentifier {
        #if DEBUG
        if usesFakeIdentifier { return FakeVehicleIdentifier() }
        #endif
        let bundled = CoreMLVehicleIdentifier()
        // A dedicated bundled classifier wins; otherwise the on-device system model, when allowed.
        guard bundled.availability != .available, usesSystemModel else { return bundled }
        return SystemModelVehicleIdentifier()
    }

    func makeDetector() -> any VehicleDetector {
        #if DEBUG
        if usesFakeDetector { return FakeVehicleDetector() }
        if !usesSystemModel { return FakeVehicleDetector(boxes: []) }
        #endif
        return VisionVehicleDetector()
    }

    func makePriceClassifier() -> any VehiclePriceClassifier {
        usesSystemModel ? SystemModelPriceClassifier() : NoPriceClassifier()
    }

    func makeSaveFault() -> (() throws -> Void)? {
        #if DEBUG
        guard failsFirstSave else { return nil }
        var hasFailed = false
        return {
            guard !hasFailed else { return }
            hasFailed = true
            throw CocoaError(.fileWriteUnknown)
        }
        #else
        return nil
        #endif
    }
}
