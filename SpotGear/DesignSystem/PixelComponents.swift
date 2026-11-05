import SwiftUI

/// Rectangle with stair-stepped corners, the base of every panel and button.
struct PixelCornerShape: InsettableShape {
    var step: CGFloat = 3
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let s = min(step, min(box.width, box.height) / 4)
        var path = Path()
        path.addLines([
            CGPoint(x: box.minX + 2 * s, y: box.minY),
            CGPoint(x: box.maxX - 2 * s, y: box.minY),
            CGPoint(x: box.maxX - 2 * s, y: box.minY + s),
            CGPoint(x: box.maxX - s, y: box.minY + s),
            CGPoint(x: box.maxX - s, y: box.minY + 2 * s),
            CGPoint(x: box.maxX, y: box.minY + 2 * s),
            CGPoint(x: box.maxX, y: box.maxY - 2 * s),
            CGPoint(x: box.maxX - s, y: box.maxY - 2 * s),
            CGPoint(x: box.maxX - s, y: box.maxY - s),
            CGPoint(x: box.maxX - 2 * s, y: box.maxY - s),
            CGPoint(x: box.maxX - 2 * s, y: box.maxY),
            CGPoint(x: box.minX + 2 * s, y: box.maxY),
            CGPoint(x: box.minX + 2 * s, y: box.maxY - s),
            CGPoint(x: box.minX + s, y: box.maxY - s),
            CGPoint(x: box.minX + s, y: box.maxY - 2 * s),
            CGPoint(x: box.minX, y: box.maxY - 2 * s),
            CGPoint(x: box.minX, y: box.minY + 2 * s),
            CGPoint(x: box.minX + s, y: box.minY + 2 * s),
            CGPoint(x: box.minX + s, y: box.minY + s),
            CGPoint(x: box.minX + 2 * s, y: box.minY + s)
        ])
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PixelCornerShape {
        PixelCornerShape(step: step, inset: inset + amount)
    }
}

/// Bordered surface standing on a darker lip, like a block in a game menu.
struct PixelPanelModifier: ViewModifier {
    var fill: Color = Theme.panel
    var border: Color = Theme.line
    var padding: CGFloat = Spacing.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .clipShape(PixelCornerShape())
            .background {
                ZStack {
                    PixelCornerShape().fill(Theme.lineDark).offset(y: Spacing.lip)
                    PixelCornerShape().fill(fill)
                }
            }
            .overlay {
                PixelCornerShape().strokeBorder(border, lineWidth: Spacing.border)
                    .allowsHitTesting(false)
            }
            .padding(.bottom, Spacing.lip)
    }
}

extension View {
    func pixelPanel(fill: Color = Theme.panel, border: Color = Theme.line, padding: CGFloat = Spacing.large) -> some View {
        modifier(PixelPanelModifier(fill: fill, border: border, padding: padding))
    }

    /// Solid footer for primary actions above the home indicator.
    func pixelBottomBar() -> some View {
        padding()
            .background {
                Theme.night
                    .overlay(alignment: .top) { Theme.lineDark.frame(height: Spacing.border) }
                    .ignoresSafeArea()
            }
    }

    /// Lets the night background show through `List` and `Form`.
    func pixelListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
    }
}

/// Chunky game button whose face sinks into its lip when pressed.
struct PixelButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case danger
    }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, kind: kind)
    }
}

private struct PixelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PixelButtonStyle.Kind

    @Environment(\.isEnabled) private var isEnabled

    private var face: Color {
        guard isEnabled else { return Theme.panelRaised }
        return switch kind {
        case .primary: Theme.gold
        case .secondary: Theme.panelRaised
        case .danger: Theme.danger
        }
    }

    private var lip: Color {
        guard isEnabled else { return Theme.lineDark }
        return switch kind {
        case .primary: Theme.goldDark
        case .secondary: Theme.lineDark
        case .danger: Theme.dangerDark
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.line }
        return switch kind {
        case .primary: Theme.night
        case .secondary, .danger: Theme.text
        }
    }

    var body: some View {
        let pressOffset = configuration.isPressed ? Spacing.lip : 0
        configuration.label
            .font(.pixelHeadline)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: Spacing.minimumTapTarget)
            .background {
                ZStack {
                    PixelCornerShape().fill(face)
                    PixelCornerShape().strokeBorder(kind == .primary && isEnabled ? Theme.goldDark : Theme.line, lineWidth: Spacing.border)
                }
            }
            .offset(y: pressOffset)
            .padding(.bottom, Spacing.lip)
            .background(alignment: .bottom) {
                PixelCornerShape().fill(lip).frame(height: Spacing.minimumTapTarget)
            }
            .contentShape(Rectangle())
    }
}

/// Segmented bar: filled blocks instead of a smooth fill. `value` is 0…1.
struct PixelProgressBar: View {
    let value: Double
    var tint: Color = Theme.lime
    var segments = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filled: Int {
        guard value > 0 else { return 0 }
        return min(max(Int((value * Double(segments)).rounded()), 1), segments)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? tint : Theme.lineDark)
                    .overlay(alignment: .top) {
                        if index < filled { Color.white.opacity(0.35).frame(height: 2) }
                    }
            }
        }
        .frame(height: 10)
        .padding(3)
        .background(Theme.night)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: Spacing.border))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: filled)
    }
}

/// Small sprites drawn from text maps, in the same blocky language as the scenes.
struct PixelSprite: View {
    enum Art {
        case heart
        case heartEmpty
        case star
        case coin
        case car
        case trophy
        case lock

        var rows: [String] {
            switch self {
            case .heart:
                [" kk kk ", "kppkppk", "kpppppk", "kpppppk", " kpppk ", "  kpk  ", "   k   "]
            case .heartEmpty:
                [" ss ss ", "s  s  s", "s     s", "s     s", " s   s ", "  s s  ", "   s   "]
            case .star:
                ["   g   ", "   g   ", "ggggggg", " ggggg ", "  ggg  ", " gg gg ", " g   g "]
            case .coin:
                ["  ggg  ", " gGGGg ", "gGgggGg", "gGgggGg", "gGgggGg", " gGGGg ", "  ggg  "]
            case .car:
                ["     rrrrrr     ", "    rbbrbbbr    ", "   rrbbrbbbrr   ", " rrrrrrrrrrrrrr ",
                 "rgrrrrrrrrrrrrgr", "rrrrrrrrrrrrrrrr", " kkkrrrrrrrrkkk ", " kskkkkkkkkkksk ", "  k          k  "]
            case .trophy:
                ["ggggggg", "gGggggg", " ggggg ", "  ggg  ", "   g   ", "  GGG  ", " ggggg "]
            case .lock:
                ["  sss  ", " s   s ", " s   s ", "sssssss", "sss sss", "sss sss", "sssssss"]
            }
        }
    }

    let art: Art
    var pixel: CGFloat = 2

    private static let colors: [Character: Color] = [
        "k": Color(hex: 0x0B1120), "p": Theme.pink, "g": Theme.gold, "G": Theme.goldDark,
        "s": Theme.textSecondary, "r": Theme.danger, "b": Theme.sky
    ]

    var body: some View {
        let rows = art.rows
        let columns = rows.map(\.count).max() ?? 0
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, symbol) in row.enumerated() {
                    guard let color = Self.colors[symbol] else { continue }
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(columns) * pixel, height: CGFloat(rows.count) * pixel)
        .accessibilityHidden(true)
    }
}

/// Arcade-font section label with a gold marker.
struct PixelSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Rectangle().fill(Theme.gold).frame(width: 6, height: 6)
            Text(title)
                .font(.pixelLabel)
                .textCase(.uppercase)
                .foregroundStyle(Theme.gold)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Segmented control made of pixel buttons; the selected one is marked by fill and a check.
struct PixelSegmentedPicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: LocalizedStringKey)]

    var body: some View {
        HStack(spacing: Spacing.small) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(kind: isSelected ? .primary : .secondary))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct PixelTextFieldStyle: TextFieldStyle {
    @Environment(\.isEnabled) private var isEnabled

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Spacing.minimumTapTarget)
            .background(PixelCornerShape().fill(Theme.night))
            .overlay(PixelCornerShape().strokeBorder(Theme.line, lineWidth: Spacing.border))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Indeterminate activity: blocks lighting up in turn. It never pretends to know a percentage.
struct PixelLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ProgressView().tint(Theme.gold)
        } else {
            TimelineView(.periodic(from: .now, by: 0.14)) { context in
                let active = Int(context.date.timeIntervalSinceReferenceDate / 0.14) % 5
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Rectangle()
                            .fill(index == active ? Theme.gold : Theme.lineDark)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Loading")
        }
    }
}

/// Generated landscape drawn with sharp, unsmoothed pixels.
struct PixelSceneView: View {
    let kind: PixelScene.Kind
    var seed: UInt64 = 7
    var width = 240
    var height = 120

    var body: some View {
        if let image = PixelScene.image(kind, seed: seed, width: width, height: height) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .accessibilityHidden(true)
        }
    }
}

/// Friendly empty and result states with a sprite on a pixel landscape.
struct PixelEmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var art: PixelSprite.Art = .car
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Spacing.large) {
            PixelSprite(art: art, pixel: 4)
            Text(title)
                .font(.pixelTitle)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            actions
        }
        .frame(maxWidth: .infinity)
        .pixelPanel(padding: Spacing.extraLarge)
    }
}

extension PixelEmptyState where Actions == EmptyView {
    init(title: LocalizedStringKey, message: LocalizedStringKey, art: PixelSprite.Art = .car) {
        self.init(title: title, message: message, art: art) { EmptyView() }
    }
}

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
            PixelSectionTitle("Identification")
            PixelProgressBar(value: 0.6)
            HStack {
                PixelSprite(art: .heart)
                PixelSprite(art: .star)
                PixelSprite(art: .coin)
                PixelSprite(art: .trophy)
                PixelSprite(art: .car, pixel: 3)
            }
            Button("Add Photo") {}.buttonStyle(PixelButtonStyle())
            Button("Edit") {}.buttonStyle(PixelButtonStyle(kind: .secondary))
            PixelLoadingIndicator()
        }
        .pixelPanel()
        .padding()
    }
    .background(Theme.night)
    .preferredColorScheme(.dark)
    .task { PixelFonts.register() }
}
