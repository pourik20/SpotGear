import CoreText
import SwiftUI
import UIKit

/// Night-sky palette of the RPG look. Colors never carry state alone; icons and text do too.
enum Theme {
    static let night = Color(hex: 0x020617)
    static let panel = Color(hex: 0x0F172A)
    static let panelRaised = Color(hex: 0x1E293B)
    static let line = Color(hex: 0x475569)
    static let lineDark = Color(hex: 0x334155)
    static let text = Color(hex: 0xF8FAFC)
    static let textSecondary = Color(hex: 0xCBD5E1)
    static let gold = Color(hex: 0xFACC21)
    static let goldDark = Color(hex: 0xA16207)
    static let lime = Color(hex: 0x84CC16)
    static let sky = Color(hex: 0x38BDF8)
    static let violet = Color(hex: 0x8B5CF6)
    static let pink = Color(hex: 0xEC4899)
    static let danger = Color(hex: 0xEF4444)
    static let dangerDark = Color(hex: 0x7F1D1D)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Bundled pixel fonts. Long text stays in the rounded system font so it remains easy to read.
enum PixelFonts {
    static let headingFamily = "Pixelify Sans"
    static let heading = "PixelifySans-Regular"
    static let arcade = "PressStart2P-Regular"

    /// Registered at runtime, so the generated Info.plist needs no font list.
    static func register() {
        for name in ["PixelifySans-Variable", "PressStart2P-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static let pixelHero = Font.custom(PixelFonts.headingFamily, size: 44, relativeTo: .largeTitle).weight(.bold)
    static let pixelTitle = Font.custom(PixelFonts.headingFamily, size: 26, relativeTo: .title2).weight(.bold)
    static let pixelHeadline = Font.custom(PixelFonts.headingFamily, size: 19, relativeTo: .headline).weight(.semibold)
    /// Arcade capitals for short labels and numbers only; they are too wide for sentences.
    static let pixelLabel = Font.custom(PixelFonts.arcade, size: 10, relativeTo: .caption2)
    static let pixelValue = Font.custom(PixelFonts.arcade, size: 13, relativeTo: .footnote)
}

/// Dark, solid navigation bars with the pixel heading font.
enum ThemeAppearance {
    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.night)
        appearance.shadowColor = UIColor(Theme.lineDark)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.text),
            .font: UIFont(name: PixelFonts.heading, size: 20) ?? .preferredFont(forTextStyle: .headline)
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
