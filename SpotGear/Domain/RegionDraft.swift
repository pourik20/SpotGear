import Foundation

enum RegionStatus: Equatable, Sendable {
    case pending
    case processing
    case needsConfirmation
    case confirmed
}

enum IdentificationState: Equatable, Sendable {
    case notStarted
    case running
    case finished(IdentificationOutcome)
    case failed

    var candidates: [VehicleCandidate] {
        if case .finished(.available(let candidates)) = self { return candidates }
        return []
    }
}

enum SegmentationState: Equatable, Sendable {
    case notStarted
    case running
    /// File name of the staged alpha cutout inside the import's staging directory.
    case available(stagedFileName: String)
    case notUsable(SegmentationFailure)

    var stagedFileName: String? {
        if case .available(let name) = self { return name }
        return nil
    }
}

/// One car selected in the imported photo, before it is saved.
struct RegionDraft: Identifiable, Equatable, Sendable {
    /// Also used as the ID of the saved Spot, which keeps retries idempotent.
    let id: UUID
    let spotPhotoID: UUID
    let number: Int
    private(set) var crop: CropRect
    private(set) var revision = 0
    var status: RegionStatus = .pending
    var input = IdentityInput()
    var identitySource: IdentitySource = .manual
    var confirmedIdentity: VehicleIdentity?
    var identification: IdentificationState = .notStarted
    var selectedCandidateLabel: String?
    var rejectedAllCandidates = false
    var segmentation: SegmentationState = .notStarted
    var cardStyle: CardStyle = .pixel

    init(id: UUID = UUID(), spotPhotoID: UUID = UUID(), number: Int, crop: CropRect = .initial) {
        self.id = id
        self.spotPhotoID = spotPhotoID
        self.number = number
        self.crop = crop.clamped()
    }

    var hasProcessingResult: Bool {
        switch identification {
        case .finished, .failed: true
        case .notStarted, .running: false
        }
    }

    /// A crop change invalidates suggestions, segmentation and confirmation; typed text stays as a draft,
    /// text that came from a suggestion goes with it.
    mutating func updateCrop(_ newCrop: CropRect) {
        let clamped = newCrop.clamped()
        guard clamped != crop else { return }
        crop = clamped
        revision += 1
        status = .pending
        confirmedIdentity = nil
        if selectedCandidateLabel != nil { input = IdentityInput(yearText: input.yearText) }
        identification = .notStarted
        segmentation = .notStarted
        selectedCandidateLabel = nil
        rejectedAllCandidates = false
        cardStyle = cardStyle.resolved(hasCutout: false)
        identitySource = .manual
    }

    /// Editing after confirmation requires a new confirmation.
    mutating func invalidateConfirmation() {
        guard status == .confirmed else { return }
        confirmedIdentity = nil
        status = hasProcessingResult ? .needsConfirmation : .pending
    }
}
