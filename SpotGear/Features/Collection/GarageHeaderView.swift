import SwiftUI

/// Hero landscape with the logo and the player panel: level, XP and collection counts.
struct GarageHeaderView: View {
    let progress: GarageProgress

    var body: some View {
        VStack(spacing: -Spacing.extraLarge) {
            hero
            playerPanel
                .padding(.horizontal)
        }
    }

    private var hero: some View {
        PixelSceneView(kind: .meadow, seed: 11, width: 240, height: 120)
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipped()
            .overlay(alignment: .top) {
                Text(verbatim: "SpotGear")
                    .font(.pixelHero)
                    .foregroundStyle(Theme.gold)
                    .shadow(color: Theme.goldDark, radius: 0, x: 0, y: 2)
                    .shadow(color: Color(hex: 0x0B1120), radius: 0, x: 2, y: 3)
                    .padding(.top, Spacing.extraLarge)
                    .accessibilityAddTraits(.isHeader)
            }
    }

    private var playerPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .center, spacing: Spacing.medium) {
                levelBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.rank.title)
                        .font(.pixelHeadline)
                        .foregroundStyle(Theme.text)
                    Text("\(progress.xpIntoLevel) / \(progress.xpForLevel) XP")
                        .font(.pixelLabel)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                PixelSprite(art: .coin, pixel: 3)
            }
            .accessibilityElement(children: .combine)

            PixelProgressBar(value: progress.levelProgress)
                .accessibilityLabel("Postup na další úroveň")
                .accessibilityValue(Text("\(progress.xpIntoLevel) z \(progress.xpForLevel) XP"))

            HStack(spacing: Spacing.small) {
                GarageStat(value: progress.spotCount, label: "Aut")
                GarageStat(value: progress.makeCount, label: "Značek")
                NavigationLink(value: AppRoute.quests) {
                    GarageStat(
                        value: progress.completedQuestCount,
                        label: "Výzev",
                        total: GarageQuest.allCases.count
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("collection.quests")
            }
        }
        .pixelPanel(border: Theme.gold.opacity(0.6))
    }

    private var levelBadge: some View {
        VStack(spacing: 4) {
            Text("LVL")
                .font(.pixelLabel)
            Text(progress.level, format: .number)
                .font(.pixelValue)
        }
        .foregroundStyle(Theme.night)
        .frame(minWidth: 52, minHeight: 52)
        .background {
            PixelCornerShape().fill(Theme.gold)
            PixelCornerShape().strokeBorder(Theme.goldDark, lineWidth: Spacing.border)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Úroveň \(progress.level)")
    }
}

private struct GarageStat: View {
    let value: Int
    let label: LocalizedStringKey
    var total: Int?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let total {
                    Text(verbatim: "\(value)/\(total)")
                } else {
                    Text(value, format: .number)
                }
            }
            .font(.pixelValue)
            .foregroundStyle(Theme.text)
            Text(label)
                .font(.pixelLabel)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: Spacing.minimumTapTarget)
        .padding(.vertical, Spacing.small)
        .background(PixelCornerShape().fill(Theme.panelRaised))
        .accessibilityElement(children: .combine)
    }
}

/// XP gained since the last change of the collection.
struct GarageReward: Equatable {
    var id = UUID()
    var xp: Int
    var newLevel: Int?

    var announcement: String {
        if let newLevel {
            String(localized: "Získáno \(xp) XP. Nová úroveň \(newLevel).")
        } else {
            String(localized: "Získáno \(xp) XP.")
        }
    }
}

struct GarageRewardBanner: View {
    let reward: GarageReward

    var body: some View {
        HStack(spacing: Spacing.small) {
            PixelSprite(art: .star, pixel: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "+\(reward.xp) XP")
                    .font(.pixelValue)
                if let level = reward.newLevel {
                    Text("Nová úroveň \(level)!")
                        .font(.pixelHeadline)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .pixelPanel(fill: Theme.panelRaised, border: Theme.gold, padding: Spacing.medium)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
