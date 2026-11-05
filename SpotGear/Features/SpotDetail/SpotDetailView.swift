import SwiftData
import SwiftUI

struct SpotDetailView: View {
    @Query private var spots: [Spot]

    init(spotID: UUID) {
        _spots = Query(filter: #Predicate<Spot> { $0.id == spotID })
    }

    var body: some View {
        if let spot = spots.first {
            SpotDetailContent(spot: spot)
        } else {
            PixelEmptyState(title: "Auto není ve sbírce", message: "Mohlo být mezitím smazáno.")
                .padding()
                .frame(maxHeight: .infinity)
                .background(Theme.night.ignoresSafeArea())
        }
    }
}

private struct SpotDetailContent: View {
    let spot: Spot

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var editsIdentity = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                cardPanel
                identityPanel
                if let identity = spot.identity {
                    VehicleInsightPanel(
                        identity: identity,
                        catalog: services.catalog,
                        priceClassifier: services.priceClassifier
                    )
                }
                explorationPanel
                datesPanel
                notePanel
                originalPhotoPanel

                VStack(alignment: .leading, spacing: Spacing.small) {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Smazat auto ze sbírky", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(kind: .danger))
                    .accessibilityIdentifier("detail.delete")
                    Text("Ostatní auta ze stejné fotografie zůstanou zachována.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle(Text(verbatim: spot.displayTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    perform { try services.library.setFavorite(spotID: spot.id, isFavorite: !spot.isFavorite) }
                } label: {
                    Label(
                        spot.isFavorite ? "Odebrat z oblíbených" : "Přidat do oblíbených",
                        systemImage: spot.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .accessibilityIdentifier("detail.favorite")
            }
        }
        .onAppear { note = spot.note }
        .onChange(of: noteFocused) { _, focused in
            if !focused { saveNote() }
        }
        .onDisappear(perform: saveNote)
        .sheet(isPresented: $editsIdentity) {
            IdentityEditSheet(spot: spot)
        }
        .confirmationDialog("Smazat toto auto?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Smazat", role: .destructive, action: delete)
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Karta, poznámka i identifikace budou odstraněny. Tuto akci nelze vrátit.")
        }
        .alert(
            "Změnu se nepodařilo uložit",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var cardPanel: some View {
        VStack(spacing: Spacing.medium) {
            SpotCardImage(request: spot.primaryPhoto?.imageRequest, style: spot.primaryPhoto?.effectiveCardStyle ?? .photo)
            if let photo = spot.primaryPhoto {
                PixelSegmentedPicker(
                    title: "Vzhled karty",
                    selection: cardStyleBinding(photo),
                    options: CardStyle.options(hasCutout: photo.cutoutPath != nil)
                )
            }
        }
        .pixelPanel(padding: Spacing.small)
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("Identifikace")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: spot.displayTitle)
                    .font(.pixelTitle)
                    .foregroundStyle(Theme.text)
                if let detail = spot.identity?.detail {
                    Text(verbatim: detail).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            identityStatus
            Button {
                editsIdentity = true
            } label: {
                Label("Upravit identifikaci", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(kind: .secondary))
            .accessibilityIdentifier("detail.editIdentity")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var explorationPanel: some View {
        let facts = spot.facts
        return VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                PixelSectionTitle("Průzkum")
                Spacer()
                Text(verbatim: "\(facts.xp) XP")
                    .font(.pixelLabel)
                    .foregroundStyle(Theme.gold)
            }
            PixelProgressBar(value: facts.completion, tint: Theme.sky, segments: 16)
                .accessibilityLabel("Vyplněné údaje")
                .accessibilityValue(Text(facts.completion, format: .percent.precision(.fractionLength(0))))
            ExplorationStep(title: "Značka", isDone: facts.hasMake)
            ExplorationStep(title: "Model", isDone: facts.hasModel)
            ExplorationStep(title: "Generace nebo rok", isDone: facts.hasDetail)
            ExplorationStep(title: "Poznámka", isDone: facts.hasNote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var datesPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            PixelSectionTitle("Datum")
            if let observedAt = spot.observedAt {
                LabeledContent("Spatřeno") {
                    Text(observedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }
            LabeledContent("Přidáno do sbírky") {
                Text(spot.createdAt, format: .dateTime.day().month().year())
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var notePanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("Poznámka")
            TextField("Přidat poznámku", text: $note, axis: .vertical)
                .lineLimit(2...8)
                .focused($noteFocused)
                .padding(.vertical, Spacing.small)
                .textFieldStyle(PixelTextFieldStyle())
                .accessibilityIdentifier("detail.note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var originalPhotoPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("Původní fotografie")
            OriginalPhotoView(path: spot.primaryPhoto?.photoAsset?.relativePath)
                .clipShape(PixelCornerShape())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel(padding: Spacing.medium)
    }

    @ViewBuilder
    private var identityStatus: some View {
        if let confirmedAt = spot.confirmedAt, spot.identity != nil {
            let source = spot.identitySource == .modelSuggestion
                ? String(localized: "z návrhu modelu")
                : String(localized: "ručně")
            Label {
                Text("Potvrzeno uživatelem (\(source)) \(confirmedAt.formatted(date: .abbreviated, time: .omitted))")
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
        } else {
            Label("Neznámé auto. Údaje můžete kdykoli doplnit.", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func cardStyleBinding(_ photo: SpotPhoto) -> Binding<CardStyle> {
        Binding(
            get: { photo.effectiveCardStyle },
            set: { style in perform { try services.library.setCardStyle(spotID: spot.id, style: style) } }
        )
    }

    private func saveNote() {
        guard note.trimmingCharacters(in: .whitespacesAndNewlines) != spot.note else { return }
        perform { try services.library.updateNote(spotID: spot.id, note: note) }
    }

    private func delete() {
        let id = spot.id
        Task {
            do {
                try await services.library.deleteSpot(id: id)
                dismiss()
            } catch {
                errorMessage = String(localized: "Auto se nepodařilo smazat. Sbírka zůstala beze změny.")
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = String(localized: "Sbírka zůstala beze změny. Zkuste to prosím znovu.")
        }
    }
}

private struct ExplorationStep: View {
    let title: LocalizedStringKey
    let isDone: Bool

    var body: some View {
        Label {
            Text(title).foregroundStyle(isDone ? Theme.text : Theme.textSecondary)
        } icon: {
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(isDone ? Theme.lime : Theme.line)
        }
        .font(.subheadline)
        .accessibilityValue(isDone ? Text("Vyplněno") : Text("Chybí"))
    }
}

private struct OriginalPhotoView: View {
    let path: String?

    @Environment(AppServices.self) private var services
    @State private var image: CGImage?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Původní fotografie")
            } else if isMissing {
                Label("Původní fotografie není dostupná.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
            } else {
                PixelLoadingIndicator().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: path) {
            guard let path else {
                isMissing = true
                return
            }
            image = await services.cardImages.source(path: path, maxPixelSize: 1600)
            isMissing = image == nil
        }
    }
}

private struct IdentityEditSheet: View {
    let spot: Spot

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var input = IdentityInput()
    @State private var validationError: IdentityValidationError?
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    IdentityFormFields(input: $input, validationError: validationError)
                    Text("Úprava nepotřebuje internet. Uložením údaje potvrzujete.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        input = IdentityInput()
                    } label: {
                        Label("Nevím – neznámé auto", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(kind: .secondary))
                    if saveFailed {
                        Label("Změnu se nepodařilo uložit. Zkuste to znovu.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.danger)
                    }
                }
                .pixelPanel()
                .padding()
            }
            .background(Theme.night.ignoresSafeArea())
            .normalizesIdentityInput($input)
            .onChange(of: input) { validationError = nil }
            .navigationTitle("Identifikace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .accessibilityIdentifier("identity.save")
                }
            }
            .onAppear { input = IdentityInput(identity: spot.identity) }
        }
    }

    private func save() {
        do {
            if let error = try services.library.updateIdentity(spotID: spot.id, input: input) {
                validationError = error
            } else {
                dismiss()
            }
        } catch {
            saveFailed = true
        }
    }
}
