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
            PixelSectionTitle("O autě")
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
            Text("Orientační cena ojetého auta")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: VehiclePriceFormat.range(insight.priceCZK))
                .font(.pixelHeadline)
                .foregroundStyle(Theme.gold)
                .accessibilityIdentifier("insight.price")
        }
        .accessibilityElement(children: .combine)

        if let generation = insight.generation {
            LabeledContent("Generace") { Text(verbatim: generation) }
        }
        LabeledContent("Vyráběno") { Text(verbatim: years(insight)) }
        if let bodyStyle = insight.bodyStyle {
            LabeledContent("Karoserie") { Text(verbatim: bodyStyle) }
        }
        if let powertrain = insight.powertrain {
            LabeledContent("Pohon") { Text(verbatim: powertrain) }
        }
        if let power = insight.powerKW {
            LabeledContent("Výkon") { Text(verbatim: "\(power.lowerBound)–\(power.upperBound) kW") }
        }

        if !insight.isGenerationSpecific {
            Text("Údaje platí pro všechny generace v katalogu. Generace nebo rok je zpřesní.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Text("Hrubý odhad z katalogu v aplikaci (stav \(catalog.priceDate)). Skutečná cena záleží na stavu, nájezdu a výbavě. Údaje se týkají typu auta, ne tohoto kusu.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private var missingContent: some View {
        Text("Toto auto v katalogu aplikace zatím není, takže cenu ani technické údaje neuvádím.")
            .foregroundStyle(Theme.textSecondary)
        if isClassifying {
            HStack(spacing: Spacing.small) {
                PixelLoadingIndicator()
                Text("Odhaduji cenovou kategorii…").foregroundStyle(Theme.textSecondary)
            }
        } else if let priceClass {
            LabeledContent("Cenová kategorie") { Text(title(of: priceClass)) }
                .accessibilityIdentifier("insight.priceClass")
            Text("Hrubý odhad modelu Apple Intelligence v zařízení, může být nepřesný.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func years(_ insight: VehicleInsight) -> String {
        if let to = insight.yearTo { return "\(insight.yearFrom)–\(to)" }
        return String(localized: "od \(String(insight.yearFrom))")
    }

    private func title(of priceClass: VehiclePriceClass) -> LocalizedStringKey {
        switch priceClass {
        case .budget: "Levná"
        case .mainstream: "Běžná"
        case .premium: "Prémiová"
        case .luxury: "Luxusní"
        case .supercar: "Superauta"
        case .collectible: "Sběratelská"
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
