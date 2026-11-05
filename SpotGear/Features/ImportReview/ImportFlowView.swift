import SwiftUI

enum ImportOutcome {
    case completed
    case cancelled
    case failed(ImportError)
}

/// Container for one import. Shows the screen matching the session phase.
struct ImportFlowView: View {
    let session: ImportSession
    let onFinish: (ImportOutcome) -> Void

    @State private var path: [UUID] = []
    @State private var confirmsCancel = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar {
                    if session.phase != .saving {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                if session.regions.isEmpty { cancel() } else { confirmsCancel = true }
                            }
                            .accessibilityIdentifier("import.cancel")
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { regionID in
                    RegionConfirmView(session: session, regionID: regionID)
                }
        }
        .interactiveDismissDisabled()
        .onChange(of: session.phase) { _, phase in
            if phase == .completed { onFinish(.completed) }
        }
        .onChange(of: session.loadError) { _, error in
            if let error { onFinish(.failed(error)) }
        }
        .confirmationDialog("Discard This Import?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: cancel)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The selected cars won't be saved.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle, .loading:
            VStack(spacing: Spacing.large) {
                PixelLoadingIndicator()
                Text("Loading photo…")
                    .font(.pixelHeadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle("New Photo")
            .navigationBarTitleDisplayMode(.inline)
        case .detecting:
            DetectingView(image: session.workingImage)
        case .selecting:
            RegionSelectionView(session: session) { path.append($0) }
        case .reviewing, .saving, .completed:
            ImportSummaryView(session: session)
        }
    }

    private func cancel() {
        Task {
            await session.cancel()
            onFinish(.cancelled)
        }
    }
}

/// The photo with a status line while local detection looks for cars.
private struct DetectingView: View {
    let image: CGImage?

    var body: some View {
        VStack(spacing: Spacing.large) {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 460)
                    .clipShape(PixelCornerShape())
            }
            HStack(spacing: Spacing.small) {
                PixelLoadingIndicator()
                Text("Detecting cars…")
                    .font(.pixelHeadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle("New Photo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
