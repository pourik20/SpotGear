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
            PixelEmptyState(title: "Car Not Found", message: "This car may have been deleted.")
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
                        priceClassifier: services.priceClassifier,
                        showsRewardPreview: false
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
                        Label("Delete Car", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(kind: .danger))
                    .accessibilityIdentifier("detail.delete")
                    Text("Other cars from the same photo will be kept.")
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
                        spot.isFavorite ? "Remove from Favorites" : "Add to Favorites",
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
        .confirmationDialog("Delete This Car?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The card, note, and identification will be permanently deleted.")
        }
        .alert(
            "Unable to Save Changes",
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
                    title: "Card Style",
                    selection: cardStyleBinding(photo),
                    options: CardStyle.options(hasCutout: photo.cutoutPath != nil)
                )
            }
        }
        .pixelPanel(border: spot.rewardRarity.color, padding: Spacing.small)
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("Identification")
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
                Label("Edit Identification", systemImage: "pencil")
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
                PixelSectionTitle("Discovery")
                Spacer()
            }
            RarityBadge(rarity: spot.rewardRarity, xp: facts.xp)
            if let price = spot.rewardPriceUpperCZK {
                LabeledContent("Price Used for Reward") {
                    Text(verbatim: "\(price.formatted()) CZK")
                }
                Text("Rarity uses the upper catalog price at the time of identification. Later price updates do not change this reward.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No catalog price yet. You receive 25 XP until a price becomes available.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            PixelProgressBar(value: facts.completion, tint: Theme.sky, segments: 16)
                .accessibilityLabel("Details completed")
                .accessibilityValue(Text(facts.completion, format: .percent.precision(.fractionLength(0))))
            ExplorationStep(title: "Make", isDone: facts.hasMake)
            ExplorationStep(title: "Model", isDone: facts.hasModel)
            ExplorationStep(title: "Generation or Year", isDone: facts.hasDetail)
            ExplorationStep(title: "Note", isDone: facts.hasNote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var datesPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            PixelSectionTitle("Date")
            if let observedAt = spot.observedAt {
                LabeledContent("Spotted") {
                    Text(observedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }
            LabeledContent("Added to Collection") {
                Text(spot.createdAt, format: .dateTime.day().month().year())
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }

    private var notePanel: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("Note")
            TextField("Add a note", text: $note, axis: .vertical)
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
            PixelSectionTitle("Original Photo")
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
                ? String(localized: "model suggestion")
                : String(localized: "manual entry")
            Label {
                Text("Confirmed by you (\(source)) on \(confirmedAt.formatted(date: .abbreviated, time: .omitted))")
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
        } else {
            Label("Unknown car. You can add details at any time.", systemImage: "questionmark.circle")
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
                errorMessage = String(localized: "Couldn't delete the car. Your collection is unchanged.")
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = String(localized: "Your collection is unchanged. Please try again.")
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
        .accessibilityValue(isDone ? Text("Complete") : Text("Missing"))
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
                    .accessibilityLabel("Original Photo")
            } else if isMissing {
                Label("The original photo is unavailable.", systemImage: "exclamationmark.triangle")
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
                    Text("Editing works offline. Saving confirms these details.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        input = IdentityInput()
                    } label: {
                        Label("Mark as Unknown", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(kind: .secondary))
                    if saveFailed {
                        Label("Couldn't save your changes. Please try again.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.danger)
                    }
                }
                .pixelPanel()
                .padding()
            }
            .background(Theme.night.ignoresSafeArea())
            .normalizesIdentityInput($input)
            .onChange(of: input) { validationError = nil }
            .navigationTitle("Identification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
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
