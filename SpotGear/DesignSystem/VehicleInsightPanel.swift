import SwiftUI

/// Approximate price and basic data for a car type. Shown while confirming a car and in its detail.
struct VehicleInsightPanel: View {
    let identity: VehicleIdentity
    let catalog: VehicleCatalog
    let priceClassifier: any VehiclePriceClassifier

    @State private var priceClass: VehiclePriceClass?
    @State private var isClassifying = false

    private var insight: VehicleInsight? { catalog.insight(for: identity) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            PixelSectionTitle("About This Car")
            if let insight {
                catalogContent(insight)
            } else {
                missingContent
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
        .accessibilityIdentifier("insight.panel")
        .task(id: identity.title) { await classifyIfNeeded() }
    }

    @ViewBuilder
    private func catalogContent(_ insight: VehicleInsight) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Estimated Used Price")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: VehiclePriceFormat.range(insight.priceCZK))
                .font(.pixelHeadline)
                .foregroundStyle(Theme.gold)
                .accessibilityIdentifier("insight.price")
        }
        .accessibilityElement(children: .combine)

        if let generation = insight.generation {
            LabeledContent("Generation") { Text(verbatim: generation) }
        }
        LabeledContent("Production Years") { Text(verbatim: years(insight)) }
        if let bodyStyle = insight.bodyStyle {
            LabeledContent("Body Style") { Text(verbatim: bodyStyle) }
        }
        if let powertrain = insight.powertrain {
            LabeledContent("Powertrain") { Text(verbatim: powertrain) }
        }
        if let power = insight.powerKW {
            LabeledContent("Power") { Text(verbatim: "\(power.lowerBound)–\(power.upperBound) kW") }
        }

        if !insight.isGenerationSpecific {
            Text("These figures cover all cataloged generations. Add a generation or year for more specific details.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Text("Rough catalog estimate as of \(catalog.priceDate). Actual prices depend on condition, mileage, and equipment. These figures describe the model, not this specific car.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private var missingContent: some View {
        Text("This car isn't in the catalog yet. Price estimates and specifications are unavailable.")
            .foregroundStyle(Theme.textSecondary)
        if isClassifying {
            HStack(spacing: Spacing.small) {
                PixelLoadingIndicator()
                Text("Estimating price category…").foregroundStyle(Theme.textSecondary)
            }
        } else if let priceClass {
            LabeledContent("Price Category") { Text(title(of: priceClass)) }
                .accessibilityIdentifier("insight.priceClass")
            Text("A rough estimate from Apple Intelligence on your device. It may be inaccurate.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func years(_ insight: VehicleInsight) -> String {
        if let to = insight.yearTo { return "\(insight.yearFrom)–\(to)" }
        return String(localized: "Since \(String(insight.yearFrom))")
    }

    private func title(of priceClass: VehiclePriceClass) -> LocalizedStringKey {
        switch priceClass {
        case .budget: "Budget"
        case .mainstream: "Mainstream"
        case .premium: "Premium"
        case .luxury: "Luxury"
        case .supercar: "Supercar"
        case .collectible: "Collectible"
        }
    }

    /// Debounced, because the identity changes with every typed letter in the confirmation form.
    private func classifyIfNeeded() async {
        priceClass = nil
        guard insight == nil else { return }
        do {
            try await Task.sleep(for: .milliseconds(600))
            isClassifying = true
            defer { isClassifying = false }
            priceClass = try await priceClassifier.classify(identity)
        } catch {
            priceClass = nil
        }
    }
}
