import SwiftUI

@main
struct SpotGearApp: App {
    @State private var services: Result<AppServices, Error> = Result { try AppServices.live() }

    init() {
        PixelFonts.register()
        ThemeAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch services {
                case .success(let services):
                    RootView()
                        .environment(services)
                        .modelContainer(services.container)
                case .failure:
                    StoreErrorView()
                }
            }
            .preferredColorScheme(.dark)
            .font(.system(.body, design: .rounded))
            .tint(Theme.gold)
        }
    }
}
