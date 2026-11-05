import SwiftUI

struct SpotCardView: View {
    let spot: Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpotCardImage(
                request: spot.primaryPhoto?.imageRequest,
                style: spot.primaryPhoto?.effectiveCardStyle ?? .photo
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(verbatim: spot.displayTitle)
                        .font(.pixelHeadline)
                        .foregroundStyle(spot.identity == nil ? Theme.textSecondary : Theme.text)
                    Spacer(minLength: 0)
                    if spot.isFavorite {
                        PixelSprite(art: .heart)
                    }
                }
                if let detail = spot.identity?.detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(spot.displayDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Spacing.small) {
                    PixelProgressBar(value: spot.facts.completion, tint: Theme.sky, segments: 4)
                    Text(verbatim: "\(spot.facts.xp) XP")
                        .font(.pixelLabel)
                        .foregroundStyle(Theme.gold)
                        .fixedSize()
                }
            }
            .padding(Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel(padding: 0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("spot.card")
    }

    private var accessibilitySummary: String {
        var parts = [spot.displayTitle]
        if let detail = spot.identity?.detail { parts.append(detail) }
        let date = spot.displayDate.formatted(date: .long, time: .omitted)
        parts.append(spot.observedAt == nil
            ? String(localized: "přidáno \(date)")
            : String(localized: "spatřeno \(date)"))
        if spot.isFavorite { parts.append(String(localized: "oblíbené")) }
        parts.append(String(localized: "\(spot.facts.xp) XP"))
        return parts.joined(separator: ", ")
    }
}
