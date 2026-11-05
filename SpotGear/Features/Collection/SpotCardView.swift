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
                RarityBadge(rarity: spot.rewardRarity, xp: spot.facts.xp)
            }
            .padding(Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel(border: spot.rewardRarity.color, padding: 0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("spot.card")
    }

    private var rarityAccessibilityTitle: String {
        switch spot.rewardRarity {
        case .unknown: String(localized: "Undetermined Rarity")
        case .common: String(localized: "Common")
        case .uncommon: String(localized: "Uncommon")
        case .rare: String(localized: "Rare")
        case .epic: String(localized: "Epic")
        case .legendary: String(localized: "Legendary")
        case .mythic: String(localized: "Mythic")
        }
    }

    private var accessibilitySummary: String {
        var parts = [spot.displayTitle]
        if let detail = spot.identity?.detail { parts.append(detail) }
        let date = spot.displayDate.formatted(date: .long, time: .omitted)
        parts.append(spot.observedAt == nil
            ? String(localized: "added \(date)")
            : String(localized: "spotted \(date)"))
        if spot.isFavorite { parts.append(String(localized: "favorite")) }
        parts.append(String(localized: "\(spot.facts.xp) XP"))
        parts.append(rarityAccessibilityTitle)
        return parts.joined(separator: ", ")
    }
}
