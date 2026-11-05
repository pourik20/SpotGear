import SwiftUI

/// A cutout standing in a seamless photo studio: soft backdrop, key light, contact shadow and a faint
/// floor reflection. Only light and shadow are added around the car; the car itself is drawn as is.
struct StudioStage: View {
    let cutout: CGImage

    @Environment(\.colorScheme) private var colorScheme

    /// Where the wheels touch the floor, as a share of the stage height.
    private static let floorLine = 0.8
    private static let maxCarWidth = 0.84
    private static let maxCarHeight = 0.62

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let car = carSize(in: size)
            let floorY = size.height * Self.floorLine
            let centerX = size.width / 2

            ZStack(alignment: .topLeading) {
                StudioBackdrop(floorY: floorY)

                carImage
                    .scaleEffect(x: 1, y: -1)
                    .frame(width: car.width, height: car.height)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.28)
                        )
                    }
                    .opacity(colorScheme == .dark ? 0.08 : 0.12)
                    .position(x: centerX, y: floorY + car.height / 2)

                Ellipse()
                    .fill(.black.opacity(colorScheme == .dark ? 0.5 : 0.22))
                    .frame(width: car.width * 1.02, height: max(car.height * 0.16, 6))
                    .blur(radius: max(car.height * 0.06, 3))
                    .position(x: centerX, y: floorY - car.height * 0.02)

                // The silhouette's own shadow follows every contact edge, including rear wheels set
                // higher in a three-quarter view, so the car sits on the floor instead of floating.
                carImage
                    .frame(width: car.width, height: car.height)
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.55 : 0.3),
                        radius: max(car.height * 0.02, 1.5),
                        x: 0,
                        y: max(car.height * 0.025, 1.5)
                    )
                    .position(x: centerX, y: floorY - car.height / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var carImage: some View {
        Image(decorative: cutout, scale: 1)
            .resizable()
            .interpolation(.high)
    }

    private func carSize(in stage: CGSize) -> CGSize {
        let aspect = cutout.height > 0 ? Double(cutout.width) / Double(cutout.height) : 1
        let width = min(stage.width * Self.maxCarWidth, stage.height * Self.maxCarHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }
}

/// Seamless cyclorama: a wall that bends into the floor, lit from above with a gentle vignette.
struct StudioBackdrop: View {
    var floorY: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let horizon = size.height > 0 ? floorY / size.height : 0.8
            let palette = Palette(colorScheme)

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: palette.wallTop, location: 0),
                        .init(color: palette.wallBottom, location: max(horizon - 0.12, 0)),
                        .init(color: palette.floorNear, location: horizon + 0.04),
                        .init(color: palette.floorFront, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [palette.keyLight, .clear],
                    center: UnitPoint(x: 0.5, y: horizon - 0.25),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.6
                )
                RadialGradient(
                    colors: [.clear, palette.vignette],
                    center: UnitPoint(x: 0.5, y: horizon - 0.15),
                    startRadius: min(size.width, size.height) * 0.45,
                    endRadius: max(size.width, size.height) * 0.85
                )
            }
        }
    }

    private struct Palette {
        var wallTop: Color
        var wallBottom: Color
        var floorNear: Color
        var floorFront: Color
        var keyLight: Color
        var vignette: Color

        init(_ scheme: ColorScheme) {
            if scheme == .dark {
                wallTop = Color(red: 0.10, green: 0.105, blue: 0.115)
                wallBottom = Color(red: 0.19, green: 0.195, blue: 0.21)
                floorNear = Color(red: 0.16, green: 0.165, blue: 0.18)
                floorFront = Color(red: 0.07, green: 0.075, blue: 0.085)
                keyLight = .white.opacity(0.10)
                vignette = .black.opacity(0.45)
            } else {
                wallTop = Color(red: 0.80, green: 0.795, blue: 0.785)
                wallBottom = Color(red: 0.93, green: 0.925, blue: 0.915)
                floorNear = Color(red: 0.88, green: 0.875, blue: 0.865)
                floorFront = Color(red: 0.74, green: 0.735, blue: 0.725)
                keyLight = .white.opacity(0.55)
                vignette = .black.opacity(0.18)
            }
        }
    }
}

#Preview("Studio") {
    VStack(spacing: Spacing.large) {
        if let car = PreviewCutout.make() {
            CardFrame { StudioStage(cutout: car) }
            CardFrame { StudioStage(cutout: car) }.environment(\.colorScheme, .dark)
        }
    }
    .padding()
}

/// Simple car silhouette for previews only; never shown in the running app.
private enum PreviewCutout {
    static func make() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 600, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(red: 0.62, green: 0.08, blue: 0.1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 10, y: 50, width: 580, height: 100), cornerWidth: 40, cornerHeight: 40, transform: nil))
        context.addPath(CGPath(roundedRect: CGRect(x: 140, y: 120, width: 300, height: 100), cornerWidth: 50, cornerHeight: 50, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        context.fillEllipse(in: CGRect(x: 90, y: 0, width: 110, height: 110))
        context.fillEllipse(in: CGRect(x: 400, y: 0, width: 110, height: 110))
        return context.makeImage()
    }
}
