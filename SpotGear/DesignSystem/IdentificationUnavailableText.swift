import SwiftUI

/// Truthful explanation of why automatic identification is not offered, with the manual fallback.
struct IdentificationUnavailableText: View {
    let reason: IdentificationUnavailableReason

    var body: some View {
        switch reason {
        case .modelMissing, .invalidManifest, .unsupportedModel:
            Text("Automatická identifikace není v této verzi dostupná. Údaje můžete doplnit ručně.")
        case .systemUnsupported:
            Text("Automatická identifikace vyžaduje iOS 27 a zařízení s Apple Intelligence. Údaje můžete doplnit ručně.")
        case .deviceNotEligible:
            Text("Toto zařízení nepodporuje Apple Intelligence, automatická identifikace proto není dostupná. Údaje můžete doplnit ručně.")
        case .appleIntelligenceDisabled:
            Text("Pro návrhy zapněte Apple Intelligence v Nastavení systému. Do té doby můžete údaje doplnit ručně.")
        case .modelNotReady:
            Text("Model Apple Intelligence se v zařízení ještě připravuje. Zkuste to později, nebo údaje doplňte ručně.")
        }
    }
}
