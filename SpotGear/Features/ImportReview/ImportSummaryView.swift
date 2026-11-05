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
                        Button("Odebrat", systemImage: "trash", role: .destructive) {
                            session.removeRegion(region.id)
                        }
                    }
                    .accessibilityAction(named: "Odebrat auto \(region.number)") {
                        session.removeRegion(region.id)
                    }
                }
                .listRowBackground(Theme.panel)
            } header: {
                PixelSectionTitle("Zkontrolujte každé auto")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if session.unconfirmedCount > 0 {
                        Text("Potvrďte nebo odeberte všechna auta. Zbývá potvrdit: \(session.unconfirmedCount).")
                    }
                    if session.detection != nil, session.detection != .unavailable {
                        Text("Auta našel lokální rozpoznávač. Chybí nějaké, třeba zakryté v pozadí? Přidáte ho přes „Upravit výběr“.")
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
                        Text("Ukládám…")
                    } else {
                        Text("Uložit \(session.regions.count) aut")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle())
            .disabled(!session.canSave)
            .accessibilityIdentifier("summary.save")
            .pixelBottomBar()
        }
        .navigationTitle("Souhrn")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Upravit výběr") { session.returnToSelection() }
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
                Text("Auto \(region.number)")
                    .font(.pixelLabel)
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: title)
                    .font(.pixelHeadline)
                RegionStatusLabel(status: region.status)
                if let price = session.catalog.insight(for: region.confirmedIdentity)?.priceCZK {
                    Text(verbatim: VehiclePriceFormat.range(price))
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let identity = region.confirmedIdentity { return identity.title }
        if region.status == .confirmed { return String(localized: "Neznámé auto") }
        if let candidate = region.identification.candidates.first {
            return String(localized: "Návrh: \(candidate.identity.title)")
        }
        return String(localized: "Nepotvrzeno")
    }
}
