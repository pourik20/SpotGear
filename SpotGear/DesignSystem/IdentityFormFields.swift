import SwiftUI

/// Make / model / generation / year fields shared by import confirmation and spot editing.
/// Without a make the dependent fields are cleared and disabled: the car is unknown.
struct IdentityFormFields: View {
    @Binding var input: IdentityInput
    var validationError: IdentityValidationError?

    var body: some View {
        fields
            .textFieldStyle(PixelTextFieldStyle())

        if !input.hasMake {
            Text("Leave the make blank to save this as an unknown car. You can add details later.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if let validationError {
            Label(validationError.message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.danger)
                .accessibilityIdentifier("identity.error")
        }
    }

    @ViewBuilder
    private var fields: some View {
        TextField("Make", text: $input.make)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .accessibilityIdentifier("identity.make")
        TextField("Model", text: $input.model)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .disabled(!input.hasMake)
            .accessibilityIdentifier("identity.model")
        TextField("Generation (optional)", text: $input.generation)
            .autocorrectionDisabled()
            .disabled(!input.hasMake)
            .accessibilityIdentifier("identity.generation")
        TextField("Year (optional)", text: $input.yearText)
            .keyboardType(.numberPad)
            .disabled(!input.hasMake)
            .accessibilityIdentifier("identity.year")
    }
}

/// Clears dependent fields as soon as the make becomes empty.
struct IdentityInputNormalizer: ViewModifier {
    @Binding var input: IdentityInput

    func body(content: Content) -> some View {
        content.onChange(of: input.hasMake) { _, hasMake in
            if !hasMake { input = input.normalizedForMake() }
        }
    }
}

extension View {
    func normalizesIdentityInput(_ input: Binding<IdentityInput>) -> some View {
        modifier(IdentityInputNormalizer(input: input))
    }
}
