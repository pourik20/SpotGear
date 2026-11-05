import SwiftUI

/// Truthful explanation of why automatic identification is not offered, with the manual fallback.
struct IdentificationUnavailableText: View {
    let reason: IdentificationUnavailableReason

    var body: some View {
        switch reason {
        case .modelMissing, .invalidManifest, .unsupportedModel:
            Text("Automatic identification isn't available in this version. You can enter the details manually.")
        case .systemUnsupported:
            Text("Automatic identification requires iOS 27 and a device with Apple Intelligence. You can enter the details manually.")
        case .deviceNotEligible:
            Text("This device doesn't support Apple Intelligence. You can enter the details manually.")
        case .appleIntelligenceDisabled:
            Text("Turn on Apple Intelligence in Settings to get suggestions. You can also enter the details manually.")
        case .modelNotReady:
            Text("Apple Intelligence is still being prepared on this device. Try again later or enter the details manually.")
        }
    }
}
