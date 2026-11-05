import SwiftUI

/// Every region must be confirmed or removed before the single batch save.
struct ImportSummaryView: View {
    let session: ImportSession

    private var isSaving: Bool { session.phase == .saving || session.phase == .completed }

    var body: some View {
        List {
            Section {
                ForEach(session.regions) { region in
                    NavigationLink(value: region.id) {
                        RegionSummaryRow(session: session, region: region)
                    }
                    .disabled(isSaving)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            session.removeRegion(region.id)
                        }
                    }
                    .accessibilityAction(named: "Remove car \(region.number)") {
                        session.removeRegion(region.id)
                    }
                }
                .listRowBackground(Theme.panel)
            } header: {
                PixelSectionTitle("Review Each Car")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if session.unconfirmedCount > 0 {
                        Text("Confirm or remove every car before saving. Remaining: \(session.unconfirmedCount).")
                    }
                    if session.detection != nil, session.detection != .unavailable {
                        Text("Cars were detected on your device. Missing a car? Use Edit Selection to add it.")
                    }
                }
            }

            if let error = session.saveError {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: error.title).font(.headline)
                            Text(verbatim: error.message)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    }
                    .accessibilityIdentifier("summary.saveError")
                }
                .listRowBackground(Theme.panel)
            }
        }
        .pixelListBackground()
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await session.save() }
            } label: {
                HStack(spacing: Spacing.small) {
                    if isSaving {
                        PixelLoadingIndicator()
                        Text("Saving…")
                    } else {
                        Text("Save Cars (\(session.regions.count))")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle())
            .disabled(!session.canSave)
            .accessibilityIdentifier("summary.save")
            .pixelBottomBar()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit Selection") { session.returnToSelection() }
                    .disabled(isSaving)
            }
        }
    }
}

private struct RegionSummaryRow: View {
    let session: ImportSession
    let region: RegionDraft

    var body: some View {
        HStack(spacing: Spacing.medium) {
            DraftCardPreview(session: session, region: region)
                .frame(width: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Car \(region.number)")
                    .font(.pixelLabel)
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: title)
                    .font(.pixelHeadline)
                RegionStatusLabel(status: region.status)
                if let price = session.catalog.insight(for: region.confirmedIdentity)?.priceCZK {
                    Text(verbatim: VehiclePriceFormat.range(price))
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                    let rarity = SpotRarity(upperPriceCZK: price.upperBound)
                    RarityBadge(rarity: rarity, xp: rarity.xp)
                } else if region.status == .confirmed {
                    RarityBadge(rarity: .unknown, xp: SpotRarity.unknown.xp)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let identity = region.confirmedIdentity { return identity.title }
        if region.status == .confirmed { return String(localized: "Unknown Car") }
        if let candidate = region.identification.candidates.first {
            return String(localized: "Suggested: \(candidate.identity.title)")
        }
        return String(localized: "Not Confirmed")
    }
}
