import SwiftUI

/// Card image of a saved spot, loaded off the main actor. A missing thumbnail is regenerated;
/// a missing source is shown as unavailable.
struct SpotCardImage: View {
    let request: CardImageRequest?
    let style: CardStyle

    @Environment(AppServices.self) private var services
    @State private var content: CardImageContent.Content = .loading

    private struct LoadKey: Hashable {
        var request: CardImageRequest?
        var style: CardStyle
    }

    var body: some View {
        CardImageContent(content: content)
            .task(id: LoadKey(request: request, style: style)) { await load() }
    }

    private func load() async {
        guard let request else {
            content = .unavailable
            return
        }
        if style == .pixel, let card = await services.cardImages.pixelCard(for: request) {
            content = .pixel(card)
        } else if style == .cutout, let path = request.cutoutPath, let cutout = await services.cardImages.cutout(path: path) {
            content = .cutout(cutout)
        } else if let thumbnail = await services.cardImages.thumbnail(for: request) {
            content = .photo(thumbnail)
        } else {
            content = .unavailable
        }
    }
}
