import SwiftData
import SwiftUI

/// Quests are recalculated from the saved spots, so they follow every edit and deletion.
struct QuestsView: View {
    @Query private var spots: [Spot]

    var body: some View {
        let progress = GarageProgress(spots: spots.map(\.facts))
        ScrollView {
            VStack(spacing: Spacing.medium) {
                ForEach(GarageQuest.allCases) { quest in
                    QuestRow(quest: quest, progress: progress.progress(of: quest))
                }
            }
            .padding()
        }
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle("Výzvy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuestRow: View {
    let quest: GarageQuest
    let progress: Int

    private var isCompleted: Bool { progress >= quest.goal }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            PixelSprite(art: isCompleted ? .trophy : .lock, pixel: 4)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(quest.title)
                    .font(.pixelHeadline)
                    .foregroundStyle(Theme.text)
                Text(quest.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Spacing.small) {
                    PixelProgressBar(
                        value: Double(progress) / Double(quest.goal),
                        tint: isCompleted ? Theme.gold : Theme.lime,
                        segments: 10
                    )
                    Text(verbatim: "\(progress)/\(quest.goal)")
                        .font(.pixelLabel)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel(border: isCompleted ? Theme.gold : Theme.line)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quest.title)
        .accessibilityValue(isCompleted ? Text("Splněno") : Text("\(progress) z \(quest.goal)"))
        .accessibilityHint(quest.summary)
    }
}
