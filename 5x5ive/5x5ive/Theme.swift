import SwiftUI

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// A color that resolves per interface style, so no asset catalog entries are needed.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension Double {
    /// Weights are shown to the tenths place regardless of unit — lb-to-kg
    /// conversion produces long decimals that would otherwise leak through.
    var formattedWeight: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum Theme {

    // MARK: Surfaces
    /// Page background.
    static let canvas = Color(light: 0xF7F5F1, dark: 0x0E0D0C)
    static let surface = Color(light: 0xFFFEFB, dark: 0x131211)
    /// The one card that currently has focus (the active exercise).
    static let surfaceActive = Color(light: 0xFFFEFB, dark: 0x151413)
    /// Recessed wells — unlogged set tiles.
    static let surfaceSunken = Color(light: 0xF2EFE9, dark: 0x141312)

    // MARK: Lines
    /// List row separators, tab bar top edge.
    static let hairline = Color(light: 0xE6E2DA, dark: 0x1A1817)
    static let border = Color(light: 0xE6E2DA, dark: 0x221F1E)
    /// Focused card border, control outlines.
    static let borderStrong = Color(light: 0xDED9D0, dark: 0x2B2826)
    /// The "next set" tile outline — the one thing the eye should find.
    static let borderFocus = Color(light: 0xA9A39A, dark: 0x4A4643)

    // MARK: Text
    static let textPrimary = Color(light: 0x17150F, dark: 0xF5F3F0)
    static let textSecondary = Color(light: 0x6B665E, dark: 0xA8A4A0)
    /// Labels, metadata.
    static let textMuted = Color(light: 0x8A857C, dark: 0x8B8783)
    /// De-emphasised metadata (last session values).
    static let textDim = Color(light: 0xA9A39A, dark: 0x5C5854)
    /// Empty-state glyphs, the em-dash in an unlogged tile.
    static let textFaint = Color(light: 0xCFC9BE, dark: 0x33302D)

    // MARK: Accents — all share chroma/lightness within a mode, hue varies
    /// oklch(0.72 0.17 145) dark / oklch(0.62 0.15 145) light — success, primary action.
    static let accent = Color(light: 0x409C48, dark: 0x54BF5C)
    /// oklch(0.85 0.14 145) dark / oklch(0.45 0.14 145) light — accent text on dark fills.
    static let accentText = Color(light: 0x036819, dark: 0x91E692)
    /// Ink used on top of a filled accent button.
    static let accentInk = Color(light: 0xF7F5F1, dark: 0x0B1A10)
    /// oklch(0.72 0.16 25) — a missed set.
    static let miss = Color(light: 0xC2413B, dark: 0xF97871)
    /// oklch(0.80 0.14 75) — deload warning.
    static let warn = Color(light: 0xA9701A, dark: 0xF2AF48)

    /// Fill behind a logged set tile / streak block.
    static var accentFill: Color { accent.opacity(0.16) }
    static var accentStroke: Color { accent.opacity(0.45) }
    static var missFill: Color { miss.opacity(0.14) }
    static var missStroke: Color { miss.opacity(0.38) }

    // MARK: Type
    // Body/UI type is the system face. Every number the user reads mid-set is
    // monospaced so digits do not jump when they change.
    enum Font {
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold).width(.standard)
        }
        static func title(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold)
        }
        static func body(_ size: CGFloat = 15) -> SwiftUI.Font {
            .system(size: size, weight: .regular)
        }
        static func numeric(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// All-caps metadata labels. Pair with `.tracking(1.4)`.
        static func label(_ size: CGFloat = 11) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    // MARK: Metrics
    enum Space {
        /// Screen side margin on list screens.
        static let screen: CGFloat = 24
        /// Screen side margin on the active workout screen (cards run wider).
        static let screenTight: CGFloat = 20
        static let cardGap: CGFloat = 10
        static let tileGap: CGFloat = 7
        static let cardPadding: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 18
        static let tile: CGFloat = 12
        static let control: CGFloat = 14
        static let sheet: CGFloat = 28
        static let chip: CGFloat = 7
    }

    /// Minimum tappable edge for a set tile. At a 393pt width with 5 columns,
    /// 20pt margins and 7pt gaps, tiles land at ~64pt — comfortably above 44.
    static let minTouchTarget: CGFloat = 44
}

struct MetaLabel: View {
    let text: String
    var color: Color = Theme.textMuted

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label())
            .tracking(1.4)
            .foregroundStyle(color)
    }
}
