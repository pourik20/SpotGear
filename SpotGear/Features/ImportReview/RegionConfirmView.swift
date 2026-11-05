import SwiftUI

/// Identification and card appearance for one region. Suggestions only prefill; the user confirms.
struct RegionConfirmView: View {
    let session: ImportSession
    let regionID: UUID

    @State private var input = IdentityInput()
    @State private var validationError: IdentityValidationError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let region = session.region(regionID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    VStack(spacing: Spacing.medium) {
                        DraftCardPreview(session: session, region: region)
                        PixelSegmentedPicker(
                            title: "Vzhled karty",
                            selection: cardStyleBinding(region),
                            options: CardStyle.options(hasCutout: region.segmentation.stagedFileName != nil)
                        )
                        SegmentationStatusText(state: region.segmentation)
                    }
                    .pixelPanel(padding: Spacing.small)

                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        PixelSectionTitle("Návrhy")
                        SuggestionsView(session: session, region: region)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pixelPanel()

                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        PixelSectionTitle("Identifikace")
                        IdentityFormFields(input: $input, validationError: validationError)
                        Button {
                            input = IdentityInput()
                            session.markUnknown(regionID)
                        } label: {
                            Label("Nevím – uložit jako neznámé auto", systemImage: "questionmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PixelButtonStyle(kind: .secondary))
                        .accessibilityIdentifier("identity.unknown")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pixelPanel()

                    if case .success(let identity?) = IdentityValidation.validate(input) {
                        VehicleInsightPanel(
                            identity: identity,
                            catalog: session.catalog,
                            priceClassifier: session.priceClassifier
                        )
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.night.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    session.updateInput(input, for: regionID)
                    if let error = session.confirm(regionID) {
                        validationError = error
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("Potvrdit auto \(region.number)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle())
                .accessibilityIdentifier("region.confirm")
                .pixelBottomBar()
            }
            .navigationTitle(Text("Auto \(region.number)"))
            .navigationBarTitleDisplayMode(.inline)
            .normalizesIdentityInput($input)
            .onAppear {
                input = region.input
                session.focus(on: regionID)
            }
            .onDisappear {
                if session.focusedRegionID == regionID { session.focus(on: nil) }
            }
            .onChange(of: input) { _, newValue in
                validationError = nil
                session.updateInput(newValue, for: regionID)
            }
            .onChange(of: region.input) { _, newValue in
                if input != newValue { input = newValue }
            }
        } else {
            PixelEmptyState(title: "Auto bylo odebráno", message: "Vraťte se zpět na souhrn.")
                .padding()
                .frame(maxHeight: .infinity)
                .background(Theme.night.ignoresSafeArea())
        }
    }

    private func cardStyleBinding(_ region: RegionDraft) -> Binding<CardStyle> {
        Binding(
            get: { region.cardStyle },
            set: { session.setCardStyle($0, for: regionID) }
        )
    }
}

/// Preview of the future card from the working image or the staged cutout.
struct DraftCardPreview: View {
    let session: ImportSession
    let region: RegionDraft

    @State private var cutout: CGImage?
    @State private var pixelCard: CGImage?

    private struct PixelKey: Hashable {
        var isPixel: Bool
        var fileName: String?
        var crop: CropRect
    }

    var body: some View {
        CardImageContent(content: content)
            .task(id: region.segmentation.stagedFileName) {
                cutout = await loadCutout(region.segmentation.stagedFileName)
            }
            .task(id: PixelKey(isPixel: region.cardStyle == .pixel, fileName: region.segmentation.stagedFileName, crop: region.crop)) {
                pixelCard = region.cardStyle == .pixel ? await renderPixelCard() : nil
            }
            .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: LocalizedStringKey {
        switch region.cardStyle {
        case .pixel: "Náhled pixelové karty"
        case .cutout: "Náhled karty ve studiu"
        case .photo: "Náhled karty s fotografickým výřezem"
        }
    }

    private var content: CardImageContent.Content {
        if region.cardStyle == .pixel { return pixelCard.map { .pixel($0) } ?? .loading }
        if region.cardStyle == .cutout, let cutout { return .cutout(cutout) }
        guard let image = session.workingImage, let crop = CardRenderer.crop(image, to: region.crop) else {
            return .unavailable
        }
        return .photo(crop)
    }

    private func renderPixelCard() async -> CGImage? {
        let crop = session.workingImage.flatMap { CardRenderer.crop($0, to: region.crop) }
        let cutout = await loadCutout(region.segmentation.stagedFileName)
        let seed = region.crop.sceneSeed
        return await Task.detached(priority: .userInitiated) {
            if let cutout, let card = PixelArt.card(cutout: cutout, seed: seed) { return card }
            return crop.flatMap(PixelArt.card(photo:))
        }.value
    }

    private func loadCutout(_ fileName: String?) async -> CGImage? {
        guard let fileName else { return nil }
        let url = session.stagedFileURL(fileName)
        return await Task.detached(priority: .userInitiated) {
            try? ImageCoding.downsampledImage(at: url, maxPixelSize: CardRenderer.thumbnailMaxPixelSize)
        }.value
    }
}

private struct SuggestionsView: View {
    let session: ImportSession
    let region: RegionDraft

    var body: some View {
        if case .unavailable(let reason) = session.identifierAvailability {
            IdentificationUnavailableText(reason: reason)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("suggestions.unavailable")
        } else {
            switch region.identification {
            case .notStarted, .running:
                HStack(spacing: Spacing.small) {
                    PixelLoadingIndicator()
                    Text("Připravuji návrhy…").foregroundStyle(Theme.textSecondary)
                }
            case .failed:
                Text("Návrhy se nepodařilo získat. Údaje můžete doplnit ručně.")
                    .foregroundStyle(Theme.textSecondary)
            case .finished(.unavailable(let reason)):
                IdentificationUnavailableText(reason: reason)
                    .foregroundStyle(Theme.textSecondary)
            case .finished(.available(let candidates)):
                if candidates.isEmpty {
                    Text("Model auto nerozpoznal a nenabídl žádné návrhy. Údaje můžete doplnit ručně.")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    candidateList(candidates)
                }
            }
        }
    }

    @ViewBuilder
    private func candidateList(_ candidates: [VehicleCandidate]) -> some View {
        if session.identifierDescriptor.providerID.hasPrefix("debug.") {
            Label("Testovací návrhy – pouze ladicí sestavení, nejde o skutečné rozpoznávání.", systemImage: "testtube.2")
                .font(.footnote)
                .foregroundStyle(Theme.gold)
        }
        if session.identifierDescriptor.providerID == SystemModelVehicleIdentifier.providerID {
            Text("Návrhy vytvořil model Apple Intelligence přímo v zařízení a mohou být nepřesné.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Text("Nejlepší návrh je předvyplněný níže. Údaje vždy potvrzujete sami.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        ForEach(candidates) { candidate in
            let isChosen = region.selectedCandidateLabel == candidate.label
            Button {
                session.chooseCandidate(candidate.label, for: region.id)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: candidate.identity.title)
                        if let generation = candidate.generation {
                            Text(verbatim: generation).font(.caption)
                        }
                    }
                    Spacer()
                    if isChosen {
                        Label("Vybráno", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(kind: isChosen ? .primary : .secondary))
            .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        }
        Button {
            session.rejectCandidates(for: region.id)
        } label: {
            HStack {
                Text("Žádný z návrhů")
                Spacer()
                if region.rejectedAllCandidates {
                    Label("Vybráno", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PixelButtonStyle(kind: region.rejectedAllCandidates ? .primary : .secondary))
        .accessibilityIdentifier("suggestions.none")
    }
}

private struct SegmentationStatusText: View {
    let state: SegmentationState

    var body: some View {
        switch state {
        case .notStarted:
            EmptyView()
        case .running:
            HStack(spacing: Spacing.small) {
                PixelLoadingIndicator()
                Text("Zkouším oddělit auto od pozadí…").foregroundStyle(Theme.textSecondary)
            }
        case .available:
            Text("Auto bylo lokálně vyříznuto; jas, kontrast a ostrost byly jen jemně doladěny. Zkontrolujte náhled; vždy můžete ponechat fotografický výřez.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        case .notUsable(let failure):
            Text(message(for: failure))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func message(for failure: SegmentationFailure) -> LocalizedStringKey {
        switch failure {
        case .unsupported:
            "Odstranění pozadí není na tomto zařízení dostupné. Karta použije fotografický výřez."
        case .ambiguous:
            "Ve výřezu je více podobně velkých objektů, nevím, které auto vyříznout. Zúžete-li výřez na jedno auto, zkusím to znovu."
        case .noInstance, .emptyMask, .failed:
            "Auto se nepodařilo spolehlivě oddělit od pozadí. Karta použije fotografický výřez."
        }
    }
}
