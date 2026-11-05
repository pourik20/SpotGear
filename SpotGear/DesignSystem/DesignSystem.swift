import SwiftUI

enum Spacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    static let border: CGFloat = 2
    static let lip: CGFloat = 4
    static let minimumTapTarget: CGFloat = 44
}

/// A 4:3 card frame. Photos fill and crop; cutouts keep their proportions on the studio stage.
struct CardFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { content }
            .clipShape(PixelCornerShape())
    }
}

/// Renders a photo crop or a cutout inside a `CardFrame`.
struct CardImageContent: View {
    enum Content {
        case loading
        case photo(CGImage)
        case cutout(CGImage)
        case pixel(CGImage)
        case unavailable
    }

    let content: Content

    var body: some View {
        CardFrame {
            switch content {
            case .loading:
                ZStack {
                    Theme.panelRaised
                    PixelLoadingIndicator()
                }
            case .photo(let image):
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            case .cutout(let image):
                StudioStage(cutout: image)
            case .pixel(let image):
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            case .unavailable:
                ZStack {
                    Theme.panelRaised
                    Label("Photo Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(Spacing.small)
                }
            }
        }
    }
}

/// Number badge for a region; fill and border differ for the selected state, not only color.
struct RegionNumberBadge: View {
    let number: Int
    var isSelected = false

    var body: some View {
        Text(number, format: .number)
            .font(.pixelLabel)
            .foregroundStyle(isSelected ? Theme.night : Theme.text)
            .frame(minWidth: 26, minHeight: 26)
            .background {
                Rectangle().fill(isSelected ? Theme.gold : Theme.panel)
                Rectangle().strokeBorder(isSelected ? Theme.goldDark : Theme.text, lineWidth: Spacing.border)
            }
            .accessibilityHidden(true)
    }
}

extension RegionStatus {
    var title: LocalizedStringKey {
        switch self {
        case .pending: "Awaiting Review"
        case .processing: "Processing…"
        case .needsConfirmation: "Awaiting Confirmation"
        case .confirmed: "Confirmed"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .processing: "hourglass"
        case .needsConfirmation: "exclamationmark.circle"
        case .confirmed: "checkmark.circle.fill"
        }
    }
}

struct RegionStatusLabel: View {
    let status: RegionStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.subheadline)
            .foregroundStyle(status == .confirmed ? Theme.lime : Theme.textSecondary)
    }
}

extension CardStyle {
    var title: LocalizedStringKey {
        switch self {
        case .pixel: "Pixel"
        case .cutout: "Studio"
        case .photo: "Photo"
        }
    }

    /// Styles to offer; the studio needs a cutout, the others always work.
    static func options(hasCutout: Bool) -> [(value: CardStyle, label: LocalizedStringKey)] {
        (hasCutout ? [.pixel, .cutout, .photo] : [.pixel, .photo]).map { ($0, $0.title) }
    }
}

extension GarageRank {
    var title: LocalizedStringKey {
        switch self {
        case .rookie: "Rookie"
        case .watcher: "Spotter"
        case .hunter: "Car Hunter"
        case .expert: "Expert"
        case .master: "Garage Master"
        case .legend: "Legend"
        }
    }
}

extension GarageQuest {
    var title: LocalizedStringKey {
        switch self {
        case .firstSpot: "First Spot"
        case .collector: "Collector"
        case .threeMakes: "Three Makes"
        case .tenMakes: "Showroom"
        case .detective: "Detective"
        case .favorites: "Fan Favorites"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .firstSpot: "Save your first car."
        case .collector: "Save 10 cars."
        case .threeMakes: "Collect cars from 3 different makes."
        case .tenMakes: "Collect cars from 10 different makes."
        case .detective: "Add a make, model, and generation or year to 5 cars."
        case .favorites: "Add 3 cars to your favorites."
        }
    }
}

extension IdentityValidationError {
    var message: String {
        switch self {
        case .modelWithoutMake: String(localized: "Enter a make before adding a model, generation, or year.")
        case .invalidYear: String(localized: "Enter a four-digit year, such as 2015.")
        }
    }
}

extension CropRect {
    /// Readable position and size for VoiceOver and the adjustment panel.
    var accessibilityDescription: String {
        let left = Int((x * 100).rounded())
        let top = Int((y * 100).rounded())
        let width = Int((self.width * 100).rounded())
        let height = Int((self.height * 100).rounded())
        return String(localized: "Left \(left)%, top \(top)%, width \(width)%, height \(height)% of the photo")
    }
}
