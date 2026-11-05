import SwiftUI

extension SpotRarity {
    var title: LocalizedStringKey {
        switch self {
        case .unknown: "Undetermined Rarity"
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        case .mythic: "Mythic"
        }
    }

    var color: Color {
        switch self {
        case .unknown, .common: Theme.textSecondary
        case .uncommon: Theme.lime
        case .rare: Theme.sky
        case .epic: Color(hex: 0xC4B5FD)
        case .legendary: Color(hex: 0xFB923C)
        case .mythic: Color(hex: 0xF87171)
        }
    }
}

struct RarityBadge: View {
    let rarity: SpotRarity
    let xp: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) {
                Text(rarity.title)
                Text(verbatim: "· \(xp) XP")
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(rarity.title)
                Text(verbatim: "\(xp) XP")
            }
        }
        .font(.pixelHeadline)
        .foregroundStyle(rarity.color)
        .accessibilityElement(children: .combine)
    }
}
