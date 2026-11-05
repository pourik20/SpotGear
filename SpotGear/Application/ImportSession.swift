import CoreGraphics
import Foundation
import Observation

/// Coordinates one import: `idle → loading → detecting → reviewing → saving → completed`.
/// `selecting` follows `detecting` when no car was found, and is reachable from `reviewing` for manual changes.
///
/// Worker results are applied only when import ID, region ID and revision match, so a cancelled or
/// outdated result never overwrites a newer choice. At most one region is processed at a time.
@MainActor
@Observable
final class ImportSession: Identifiable {
    enum Phase: Equatable {
        case idle
        case loading
        case detecting
        case selecting
        case reviewing
        case saving
        case completed
    }

    static let maximumRegions = 10

    let id = UUID()
    let identifierAvailability: IdentifierAvailability
    let catalog: VehicleCatalog
    let priceClassifier: any VehiclePriceClassifier
    private(set) var phase: Phase = .idle
    private(set) var detection: VehicleDetectionOutcome?
    private(set) var regions: [RegionDraft] = []
    private(set) var source: StagedSource?
    private(set) var workingImage: CGImage?
    private(set) var loadError: ImportError?
    private(set) var saveError: ImportError?
    private(set) var focusedRegionID: UUID?

    @ObservationIgnored private let media: any MediaStore
    @ObservationIgnored private let repository: any SpotRepository
    @ObservationIgnored private let worker: ImageWorker
    @ObservationIgnored let identifierDescriptor: IdentifierDescriptor
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var processingGeneration = 0
    @ObservationIgnored private var inFlight: (regionID: UUID, revision: Int)?
    @ObservationIgnored private var nextNumber = 1

    init(
        media: any MediaStore,
        repository: any SpotRepository,
        worker: ImageWorker,
        identifier: any VehicleIdentifier,
        catalog: VehicleCatalog = VehicleCatalog(entries: []),
        priceClassifier: any VehiclePriceClassifier = NoPriceClassifier(),
        now: @escaping () -> Date = Date.init
    ) {
        self.media = media
        self.repository = repository
        self.worker = worker
        self.identifierDescriptor = identifier.descriptor
        self.identifierAvailability = identifier.availability
        self.catalog = catalog
        self.priceClassifier = priceClassifier
        self.now = now
    }

    // MARK: Derived state

    var isEditable: Bool { phase == .selecting || phase == .reviewing }
    var canAddRegion: Bool { isEditable && regions.count < Self.maximumRegions }
    var canSave: Bool { phase == .reviewing && !regions.isEmpty && regions.allSatisfy { $0.status == .confirmed } }
    var unconfirmedCount: Int { regions.filter { $0.status != .confirmed }.count }

    func region(_ id: UUID) -> RegionDraft? {
        regions.first { $0.id == id }
    }

    func stagedFileURL(_ fileName: String) -> URL {
        media.stagingURL(importID: id, fileName: fileName)
    }

    // MARK: Loading

    func start(capturedAtFallback: Date? = nil, loader: @escaping @Sendable () async throws -> Data) {
        guard phase == .idle, loadTask == nil else { return }
        phase = .loading
        loadError = nil
        loadTask = Task { [weak self] in
            await self?.load(loader: loader, capturedAtFallback: capturedAtFallback)
        }
    }

    private func load(loader: @Sendable () async throws -> Data, capturedAtFallback: Date?) async {
        do {
            let data = try await loader()
            try Task.checkCancellation()
            var staged = try await media.stageSource(data, importID: id)
            try Task.checkCancellation()
            if staged.capturedAt == nil { staged.capturedAt = capturedAtFallback }
            let sourceURL = stagedFileURL(staged.fileName)
            let image = try await worker.loadWorkingImage(from: sourceURL)
            try Task.checkCancellation()
            source = staged
            workingImage = image
            phase = .detecting
            let outcome = try await worker.detectVehicles(sourceURL: sourceURL)
            try Task.checkCancellation()
            applyDetection(outcome)
        } catch {
            await media.discardStaging(importID: id)
            guard !(error is CancellationError), !Task.isCancelled else { return }
            loadError = ImportError(error, stage: .loading)
            phase = .idle
        }
        loadTask = nil
    }

    /// Detected cars go straight to review; manual selection remains the fallback.
    private func applyDetection(_ outcome: VehicleDetectionOutcome) {
        detection = outcome
        if case .found(let boxes) = outcome {
            for crop in VehicleDetectionRules.regions(from: boxes, limit: Self.maximumRegions) {
                regions.append(RegionDraft(number: nextNumber, crop: crop))
                nextNumber += 1
            }
        }
        if regions.isEmpty {
            phase = .selecting
        } else {
            phase = .reviewing
            scheduleProcessing()
        }
    }

    /// Cancels loading or editing and removes the staging data. Not possible while saving.
    func cancel() async {
        guard phase != .saving, phase != .completed else { return }
        loadTask?.cancel()
        loadTask = nil
        stopProcessing()
        phase = .idle
        regions = []
        workingImage = nil
        source = nil
        await worker.reset()
        await media.discardStaging(importID: id)
    }

    // MARK: Regions

    @discardableResult
    func addRegion() -> UUID? {
        guard canAddRegion else { return nil }
        let region = RegionDraft(number: nextNumber)
        nextNumber += 1
        regions.append(region)
        return region.id
    }

    func removeRegion(_ regionID: UUID) {
        guard isEditable else { return }
        regions.removeAll { $0.id == regionID }
        if focusedRegionID == regionID { focusedRegionID = nil }
        if phase == .reviewing, regions.isEmpty { phase = .selecting }
    }

    func updateCrop(_ crop: CropRect, for regionID: UUID) {
        guard isEditable, let index = index(of: regionID) else { return }
        regions[index].updateCrop(crop)
        if let inFlight, inFlight.regionID == regionID, inFlight.revision != regions[index].revision {
            // The running job is outdated; its result will be discarded.
            stopProcessing()
        }
        scheduleProcessing()
    }

    func focus(on regionID: UUID?) {
        focusedRegionID = regionID
        scheduleProcessing()
    }

    func proceedToReview() {
        guard phase == .selecting, !regions.isEmpty else { return }
        phase = .reviewing
        scheduleProcessing()
    }

    func returnToSelection() {
        guard phase == .reviewing else { return }
        phase = .selecting
        saveError = nil
    }

    // MARK: Identification

    func updateInput(_ input: IdentityInput, for regionID: UUID) {
        guard isEditable, let index = index(of: regionID) else { return }
        let normalized = input.normalizedForMake()
        guard regions[index].input != normalized else { return }
        regions[index].input = normalized
        if let label = regions[index].selectedCandidateLabel,
           let candidate = regions[index].identification.candidates.first(where: { $0.label == label }),
           IdentityInput(identity: candidate.identity).make != normalized.make
            || IdentityInput(identity: candidate.identity).model != normalized.model {
            regions[index].identitySource = .manual
            regions[index].selectedCandidateLabel = nil
        }
        regions[index].invalidateConfirmation()
    }

    /// Prefills the form from a suggestion. The user still has to confirm.
    func chooseCandidate(_ label: String, for regionID: UUID) {
        guard isEditable, let index = index(of: regionID),
              let candidate = regions[index].identification.candidates.first(where: { $0.label == label })
        else { return }
        var input = IdentityInput(identity: candidate.identity)
        input.yearText = regions[index].input.yearText
        regions[index].input = input
        regions[index].identitySource = .modelSuggestion
        regions[index].selectedCandidateLabel = label
        regions[index].rejectedAllCandidates = false
        regions[index].invalidateConfirmation()
    }

    func rejectCandidates(for regionID: UUID) {
        guard isEditable, let index = index(of: regionID) else { return }
        if regions[index].selectedCandidateLabel != nil {
            regions[index].input = IdentityInput(yearText: regions[index].input.yearText)
        }
        regions[index].selectedCandidateLabel = nil
        regions[index].rejectedAllCandidates = true
        regions[index].identitySource = .manual
        regions[index].invalidateConfirmation()
    }

    func markUnknown(_ regionID: UUID) {
        guard isEditable, let index = index(of: regionID) else { return }
        regions[index].input = IdentityInput()
        regions[index].selectedCandidateLabel = nil
        regions[index].identitySource = .manual
        regions[index].invalidateConfirmation()
    }

    /// Confirms the region with the current input; an empty make confirms an unknown car.
    @discardableResult
    func confirm(_ regionID: UUID) -> IdentityValidationError? {
        guard isEditable, let index = index(of: regionID) else { return nil }
        switch IdentityValidation.validate(regions[index].input) {
        case .failure(let error):
            return error
        case .success(let identity):
            regions[index].confirmedIdentity = identity
            if identity == nil { regions[index].identitySource = .manual }
            regions[index].status = .confirmed
            return nil
        }
    }

    func setCardStyle(_ style: CardStyle, for regionID: UUID) {
        guard isEditable, let index = index(of: regionID) else { return }
        guard style == .photo || regions[index].segmentation.stagedFileName != nil else { return }
        regions[index].cardStyle = style
    }

    // MARK: Processing

    private func scheduleProcessing() {
        guard processingTask == nil, isEditable, source != nil, nextJob() != nil else { return }
        processingGeneration += 1
        let generation = processingGeneration
        processingTask = Task { [weak self] in
            await self?.runProcessing()
            self?.processingFinished(generation: generation)
        }
    }

    private func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        processingGeneration += 1
    }

    private func processingFinished(generation: Int) {
        guard generation == processingGeneration else { return }
        processingTask = nil
        scheduleProcessing()
    }

    private func runProcessing() async {
        guard let source else { return }
        let sourceURL = stagedFileURL(source.fileName)
        while !Task.isCancelled, let job = nextJob(), let index = index(of: job.regionID) {
            regions[index].status = .processing
            regions[index].identification = .running
            regions[index].segmentation = .running
            inFlight = (job.regionID, job.revision)
            let result = await worker.process(job, sourceURL: sourceURL)
            inFlight = nil
            if let result {
                apply(result)
            } else {
                revert(job)
            }
        }
    }

    private func nextJob() -> RegionJob? {
        let eligible = regions.filter { region in
            region.status == .pending && (phase == .reviewing || region.id == focusedRegionID)
        }
        guard let region = eligible.first(where: { $0.id == focusedRegionID }) ?? eligible.first else { return nil }
        return RegionJob(importID: id, regionID: region.id, revision: region.revision, crop: region.crop)
    }

    /// Applies a worker result only when it still belongs to the current region revision.
    func apply(_ result: RegionProcessingResult) {
        guard result.importID == id,
              let index = index(of: result.regionID),
              regions[index].revision == result.revision
        else { return }
        regions[index].identification = result.identification
        regions[index].segmentation = result.segmentation
        if regions[index].status == .processing {
            regions[index].status = .needsConfirmation
            prefillTopCandidate(at: index)
        }
    }

    /// Saves typing for the common case. It stays a suggestion until the user confirms it.
    private func prefillTopCandidate(at index: Int) {
        guard !regions[index].input.hasMake, !regions[index].rejectedAllCandidates,
              let candidate = regions[index].identification.candidates.first
        else { return }
        chooseCandidate(candidate.label, for: regions[index].id)
    }

    private func revert(_ job: RegionJob) {
        guard let index = index(of: job.regionID),
              regions[index].revision == job.revision,
              regions[index].status == .processing
        else { return }
        regions[index].status = .pending
        regions[index].identification = .notStarted
        regions[index].segmentation = .notStarted
    }

    // MARK: Saving

    /// Saves all confirmed regions as one batch. A second call while saving is ignored.
    func save() async {
        guard canSave, let source else { return }
        phase = .saving
        saveError = nil
        let running = processingTask
        stopProcessing()
        await running?.value

        let snapshot = regions
        do {
            let batch = try await prepareBatch(snapshot, source: source)
            let receipt = try await media.commit(batch.files, importID: id)
            do {
                _ = try repository.save(batch.batch)
            } catch {
                await media.rollback(receipt)
                throw error
            }
            await media.finishCommit(receipt)
            phase = .completed
            await worker.reset()
            await media.discardStaging(importID: id)
        } catch {
            saveError = ImportError(error, stage: .saving)
            phase = .reviewing
        }
    }

    private func prepareBatch(_ regions: [RegionDraft], source: StagedSource) async throws -> (batch: SpotBatch, files: [StagedFile]) {
        let thumbnails = try await worker.renderThumbnails(
            sourceURL: stagedFileURL(source.fileName),
            crops: regions.map { (id: $0.id, crop: $0.crop) }
        )
        let createdAt = now()
        let assetPath = MediaPaths.asset(source.assetID)
        var files = [StagedFile(stagingName: source.fileName, finalRelativePath: assetPath)]
        var records: [SpotRecord] = []

        for (offset, region) in regions.enumerated() {
            guard let thumbnail = thumbnails[region.id] else { throw MediaError.undecodable }
            let thumbnailName = MediaPaths.thumbnailName(spotPhotoID: region.spotPhotoID, revision: region.revision)
            try await media.stageFile(thumbnail, named: thumbnailName, importID: id)
            let thumbnailPath = MediaPaths.derived(thumbnailName)
            files.append(StagedFile(stagingName: thumbnailName, finalRelativePath: thumbnailPath))

            var cutoutPath: String?
            if let stagedCutout = region.segmentation.stagedFileName {
                let path = MediaPaths.derived(MediaPaths.cutoutName(spotPhotoID: region.spotPhotoID, revision: region.revision))
                files.append(StagedFile(stagingName: stagedCutout, finalRelativePath: path))
                cutoutPath = path
            }

            let identity = region.confirmedIdentity
            // Newer first in the collection: region 1 gets the latest timestamp.
            let spotCreatedAt = createdAt.addingTimeInterval(-Double(offset) / 1000)
            records.append(SpotRecord(
                spotID: region.id,
                spotPhotoID: region.spotPhotoID,
                createdAt: spotCreatedAt,
                observedAt: source.capturedAt,
                identity: identity,
                identitySource: identity == nil ? nil : region.identitySource,
                confirmedAt: identity == nil ? nil : createdAt,
                crop: region.crop,
                revision: region.revision,
                cardStyle: region.cardStyle.resolved(hasCutout: cutoutPath != nil),
                thumbnailPath: thumbnailPath,
                cutoutPath: cutoutPath,
                attempt: attemptRecord(for: region, createdAt: createdAt)
            ))
        }

        let asset = AssetRecord(
            id: source.assetID,
            createdAt: createdAt,
            capturedAt: source.capturedAt,
            relativePath: assetPath,
            width: source.pixelWidth,
            height: source.pixelHeight
        )
        return (SpotBatch(importID: id, asset: asset, spots: records), files)
    }

    private func attemptRecord(for region: RegionDraft, createdAt: Date) -> AttemptRecord? {
        guard case .finished(let outcome) = region.identification else { return nil }
        let selected = region.identitySource == .modelSuggestion && region.confirmedIdentity != nil
            ? region.selectedCandidateLabel
            : nil
        return AttemptRecord(
            id: UUID(),
            createdAt: createdAt,
            inputRevision: region.revision,
            descriptor: identifierDescriptor,
            outcomeCode: outcome.storageCode,
            snapshot: CandidatesSnapshot(
                candidates: region.identification.candidates,
                selectedLabel: selected,
                rejectedAll: region.rejectedAllCandidates
            )
        )
    }

    private func index(of regionID: UUID) -> Int? {
        regions.firstIndex { $0.id == regionID }
    }
}
