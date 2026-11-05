import SwiftUI

/// Marks cars on the photo. Works fully without gestures through the region list and adjustment buttons.
struct RegionSelectionView: View {
    let session: ImportSession
    let onOpenRegion: (UUID) -> Void

    @State private var selectedID: UUID?
    @AccessibilityFocusState private var focusedRegion: UUID?

    private var selectedRegion: RegionDraft? {
        selectedID.flatMap(session.region)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if let image = session.workingImage {
                    RegionCanvas(
                        image: image,
                        regions: session.regions,
                        selectedID: $selectedID,
                        onChange: { id, crop in session.updateCrop(crop, for: id) }
                    )
                    .aspectRatio(CGSize(width: image.width, height: image.height), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 460)
                    .clipShape(PixelCornerShape())
                }

                if session.regions.isEmpty {
                    Text(emptyHint)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("regions.hint")
                } else if let region = selectedRegion {
                    RegionAdjustControls(region: region) { session.updateCrop($0, for: region.id) }
                }

                if !session.regions.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        PixelSectionTitle("Označená auta")
                        ForEach(session.regions) { region in
                            RegionRow(
                                region: region,
                                isSelected: region.id == selectedID,
                                onSelect: { selectedID = region.id },
                                onConfirm: { onOpenRegion(region.id) },
                                onRemove: { remove(region.id) }
                            )
                            .accessibilityFocused($focusedRegion, equals: region.id)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.night.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Spacing.medium) {
                Button {
                    if let id = session.addRegion() {
                        selectedID = id
                        focusedRegion = id
                    }
                } label: {
                    Label("Přidat auto", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(kind: .secondary))
                .disabled(!session.canAddRegion)
                .accessibilityIdentifier("regions.add")

                Button {
                    session.proceedToReview()
                } label: {
                    Text("Pokračovat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle())
                .disabled(session.regions.isEmpty)
                .accessibilityIdentifier("regions.continue")
            }
            .pixelBottomBar()
        }
        .navigationTitle("Označte auta")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedID == nil { selectedID = session.regions.last?.id }
        }
    }

    private var emptyHint: LocalizedStringKey {
        switch session.detection {
        case .found(let boxes) where boxes.isEmpty:
            "Na fotografii jsem žádné auto nenašel. Klepněte na „Přidat auto“ a rámeček posuňte na auto, které chcete uložit."
        case .unavailable:
            "Automatické hledání aut není na tomto zařízení dostupné. Klepněte na „Přidat auto“ a rámeček posuňte na auto, které chcete uložit."
        case .found, nil:
            "Klepněte na „Přidat auto“ a rámeček posuňte na auto, které chcete uložit. Na jedné fotografii můžete označit až 10 aut."
        }
    }

    private func remove(_ id: UUID) {
        session.removeRegion(id)
        if selectedID == id { selectedID = session.regions.last?.id }
    }
}

private struct RegionRow: View {
    let region: RegionDraft
    let isSelected: Bool
    let onSelect: () -> Void
    let onConfirm: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.medium) { summary; Spacer(minLength: 0); buttons }
            VStack(alignment: .leading, spacing: Spacing.small) { summary; HStack { buttons } }
        }
        .pixelPanel(border: isSelected ? Theme.gold : Theme.line, padding: Spacing.medium)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(spacing: Spacing.small) {
            RegionNumberBadge(number: region.number, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto \(region.number)")
                    .font(.pixelHeadline)
                    .foregroundStyle(Theme.text)
                if isSelected {
                    Text("Vybráno k úpravě").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                RegionStatusLabel(status: region.status)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Upravit", systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: onSelect)
            .labelStyle(.iconOnly)
            .frame(minWidth: Spacing.minimumTapTarget, minHeight: Spacing.minimumTapTarget)
            .accessibilityLabel("Upravit polohu auta \(region.number)")
        Button("Potvrdit", action: onConfirm)
            .buttonStyle(PixelButtonStyle())
            .accessibilityLabel("Potvrdit auto \(region.number)")
            .accessibilityIdentifier("regions.confirm.\(region.number)")
        Button("Odebrat", systemImage: "trash", role: .destructive, action: onRemove)
            .labelStyle(.iconOnly)
            .frame(minWidth: Spacing.minimumTapTarget, minHeight: Spacing.minimumTapTarget)
            .accessibilityLabel("Odebrat auto \(region.number)")
    }
}

/// Button alternative to drag gestures: move and resize in 5 % steps with a readable position.
struct RegionAdjustControls: View {
    let region: RegionDraft
    let onChange: (CropRect) -> Void

    static let step = 0.05
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            PixelSectionTitle("Poloha auta \(region.number)")
            Text(verbatim: region.crop.accessibilityDescription)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 140))],
                alignment: .leading,
                spacing: Spacing.small
            ) {
                adjust("Posunout vlevo", "arrow.left") { $0.moved(dx: -Self.step, dy: 0) }
                adjust("Posunout vpravo", "arrow.right") { $0.moved(dx: Self.step, dy: 0) }
                adjust("Posunout nahoru", "arrow.up") { $0.moved(dx: 0, dy: -Self.step) }
                adjust("Posunout dolů", "arrow.down") { $0.moved(dx: 0, dy: Self.step) }
                adjust("Širší", "arrow.left.and.right") { $0.resized(dWidth: Self.step, dHeight: 0) }
                adjust("Užší", "arrow.right.and.line.vertical.and.arrow.left") { $0.resized(dWidth: -Self.step, dHeight: 0) }
                adjust("Vyšší", "arrow.up.and.down") { $0.resized(dWidth: 0, dHeight: Self.step) }
                adjust("Nižší", "arrow.down.and.line.horizontal.and.arrow.up") { $0.resized(dWidth: 0, dHeight: -Self.step) }
            }
        }
    }

    private func adjust(_ title: LocalizedStringKey, _ systemImage: String, transform: @escaping (CropRect) -> CropRect) -> some View {
        Button {
            onChange(transform(region.crop))
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PixelButtonStyle(kind: .secondary))
    }
}
