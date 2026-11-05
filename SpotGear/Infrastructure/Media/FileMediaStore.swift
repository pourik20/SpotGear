import Foundation
import os

/// File storage under Application Support. Files are addressed by validated relative paths only.
///
/// Layout: `assets/` (normalized sources), `derived/` (thumbnails, cutouts), `staging/<importID>/`.
actor FileMediaStore: MediaStore {
    static let sourceMaxPixelSize = 4096
    static let minimumFreeBytes: Int64 = 50 * 1024 * 1024
    private static let stagingDirectory = "staging"

    nonisolated let rootURL: URL
    private let availableCapacity: @Sendable (URL) -> Int64?
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "SpotGear", category: "media")
    private var activeImports: Set<UUID> = []
    /// Final paths that were moved out of staging but are not yet confirmed by a database save.
    private var inFlightPaths: Set<String> = []

    init(rootURL: URL, availableCapacity: @escaping @Sendable (URL) -> Int64? = FileMediaStore.systemAvailableCapacity) {
        self.rootURL = rootURL
        self.availableCapacity = availableCapacity
    }

    static func defaultRootURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SpotGear", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    @Sendable static func systemAvailableCapacity(_ url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: Paths

    nonisolated func stagingURL(importID: UUID, fileName: String) -> URL {
        stagingDirectoryURL(importID).appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated func url(forRelativePath path: String) -> URL? {
        MediaPaths.isSafe(path) ? rootURL.appendingPathComponent(path, isDirectory: false) : nil
    }

    private nonisolated func stagingDirectoryURL(_ importID: UUID) -> URL {
        rootURL
            .appendingPathComponent(Self.stagingDirectory, isDirectory: true)
            .appendingPathComponent(importID.uuidString, isDirectory: true)
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".")
    }

    // MARK: Staging

    func stageSource(_ data: Data, importID: UUID) throws -> StagedSource {
        activeImports.insert(importID)
        let directory = stagingDirectoryURL(importID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try ensureFreeSpace(atLeast: Int64(data.count) * 2 + Self.minimumFreeBytes)

        let normalized = try ImageCoding.normalize(data: data, maxPixelSize: Self.sourceMaxPixelSize)
        let fileName = "source.jpg"
        try normalized.jpegData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return StagedSource(
            importID: importID,
            assetID: UUID(),
            fileName: fileName,
            pixelWidth: normalized.width,
            pixelHeight: normalized.height,
            capturedAt: normalized.capturedAt
        )
    }

    func stageFile(_ data: Data, named fileName: String, importID: UUID) throws {
        guard Self.isSafeFileName(fileName) else { throw MediaError.unsafePath }
        let directory = stagingDirectoryURL(importID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try ensureFreeSpace(atLeast: Int64(data.count) + Self.minimumFreeBytes)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    func discardStaging(importID: UUID) {
        activeImports.remove(importID)
        removeItemIfPresent(stagingDirectoryURL(importID))
    }

    // MARK: Commit

    func commit(_ files: [StagedFile], importID: UUID) throws -> CommitReceipt {
        var moved: [StagedFile] = []
        do {
            for file in files {
                guard Self.isSafeFileName(file.stagingName),
                      let destination = url(forRelativePath: file.finalRelativePath)
                else { throw MediaError.unsafePath }
                let source = stagingURL(importID: importID, fileName: file.stagingName)
                guard fileManager.fileExists(atPath: source.path) else { throw MediaError.missingStagedFile }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                inFlightPaths.insert(file.finalRelativePath)
                try fileManager.moveItem(at: source, to: destination)
                moved.append(file)
            }
        } catch {
            rollback(CommitReceipt(importID: importID, files: moved))
            for file in files { inFlightPaths.remove(file.finalRelativePath) }
            throw error
        }
        return CommitReceipt(importID: importID, files: moved)
    }

    func rollback(_ receipt: CommitReceipt) {
        let directory = stagingDirectoryURL(receipt.importID)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in receipt.files.reversed() {
            defer { inFlightPaths.remove(file.finalRelativePath) }
            guard let source = url(forRelativePath: file.finalRelativePath) else { continue }
            let destination = directory.appendingPathComponent(file.stagingName)
            do {
                removeItemIfPresent(destination)
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                // Left in place; the next launch sweep removes it if nothing references it.
                logger.error("Rollback move failed (\((error as NSError).code))")
            }
        }
    }

    func finishCommit(_ receipt: CommitReceipt) {
        for file in receipt.files { inFlightPaths.remove(file.finalRelativePath) }
    }

    // MARK: Library files

    func writeFile(_ data: Data, relativePath: String) throws {
        guard let destination = url(forRelativePath: relativePath) else { throw MediaError.unsafePath }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    func deleteFiles(relativePaths: [String]) {
        for path in relativePaths {
            guard let url = url(forRelativePath: path) else { continue }
            removeItemIfPresent(url)
        }
    }

    func sweepOrphans(referencedPaths: Set<String>) {
        let stagingRoot = rootURL.appendingPathComponent(Self.stagingDirectory, isDirectory: true)
        for directory in contents(of: stagingRoot) {
            if let id = UUID(uuidString: directory.lastPathComponent), activeImports.contains(id) { continue }
            removeItemIfPresent(directory)
        }

        var removed = 0
        for folder in [MediaPaths.assetsDirectory, MediaPaths.derivedDirectory] {
            for file in contents(of: rootURL.appendingPathComponent(folder, isDirectory: true)) {
                let relativePath = "\(folder)/\(file.lastPathComponent)"
                guard !referencedPaths.contains(relativePath), !inFlightPaths.contains(relativePath) else { continue }
                removeItemIfPresent(file)
                removed += 1
            }
        }
        if removed > 0 { logger.info("Removed \(removed) orphaned media files") }
    }

    func deleteAllMedia() {
        removeItemIfPresent(rootURL.appendingPathComponent(MediaPaths.assetsDirectory, isDirectory: true))
        removeItemIfPresent(rootURL.appendingPathComponent(MediaPaths.derivedDirectory, isDirectory: true))
        inFlightPaths.removeAll()
    }

    // MARK: Helpers

    private func ensureFreeSpace(atLeast bytes: Int64) throws {
        let probe = fileManager.fileExists(atPath: rootURL.path) ? rootURL : rootURL.deletingLastPathComponent()
        if let available = availableCapacity(probe), available < bytes {
            throw MediaError.insufficientSpace
        }
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func removeItemIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logger.error("Cleanup failed (\((error as NSError).code)); will retry on next launch")
        }
    }
}
