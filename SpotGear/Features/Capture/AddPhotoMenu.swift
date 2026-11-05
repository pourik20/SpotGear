import SwiftUI

struct AddPhotoActions {
    var takePhoto: () -> Void
    var choosePhoto: () -> Void
    /// Only set in debug builds.
    var useTestPhoto: (() -> Void)?
}

/// The single entry point for adding a photo: camera, library and (debug only) a synthetic test photo.
struct AddPhotoMenu<MenuLabel: View>: View {
    let actions: AddPhotoActions
    @ViewBuilder var label: MenuLabel

    var body: some View {
        Menu {
            Button("Take Photo", systemImage: "camera", action: actions.takePhoto)
            Button("Choose from Library", systemImage: "photo.on.rectangle", action: actions.choosePhoto)
            if let useTestPhoto = actions.useTestPhoto {
                Button("Sample Photo", systemImage: "testtube.2", action: useTestPhoto)
                    .accessibilityIdentifier("add.testPhoto")
            }
        } label: {
            label
        }
        .accessibilityIdentifier("add.menu")
    }
}
