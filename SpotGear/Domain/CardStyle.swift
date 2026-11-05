/// Appearance of a photo card. `photo` and `pixel` need only the crop; `cutout` needs a cutout file.
enum CardStyle: String, Codable, CaseIterable, Sendable {
    case photo
    case cutout
    case pixel

    /// A cutout without a file falls back to the photo crop.
    func resolved(hasCutout: Bool) -> CardStyle {
        self == .cutout && !hasCutout ? .photo : self
    }
}

enum SegmentationFailure: String, Equatable, Sendable {
    case unsupported
    case noInstance
    case ambiguous
    case emptyMask
    case failed
}
