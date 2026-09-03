import SwiftUI

/// Mirror of `Theme.swift`'s values, since the app target's Theme.swift
/// isn't in the widget extension's Sources phase. Prefer adding it there
/// and deleting this file instead — two sources of truth will drift.
enum LATheme {

    static let textPrimary   = Color(light: 0x17150F, dark: 0xF5F3F0)
    static let textSecondary = Color(light: 0x6B665E, dark: 0xA8A4A0)
    static let textMuted     = Color(light: 0x8A857C, dark: 0x8B8783)
    static let textDim       = Color(light: 0xA9A39A, dark: 0x5C5854)
    static let textFaint     = Color(light: 0xCFC9BE, dark: 0x33302D)

    static let accent     = Color(light: 0x409C48, dark: 0x54BF5C)
    static let accentText = Color(light: 0x036819, dark: 0x91E692)
    static let accentInk  = Color(light: 0xF7F5F1, dark: 0x0B1A10)
    static let miss       = Color(light: 0xC2413B, dark: 0xF97871)

    static let surfaceSunken = Color(light: 0xF2EFE9, dark: 0x141312)
    static let hairline      = Color(light: 0xE6E2DA, dark: 0x1A1817)
    static let border        = Color(light: 0xE6E2DA, dark: 0x221F1E)
    static let borderStrong  = Color(light: 0xDED9D0, dark: 0x2B2826)
    static let borderFocus   = Color(light: 0xA9A39A, dark: 0x4A4643)

    static var accentFill: Color { accent.opacity(0.16) }
    static var accentStroke: Color { accent.opacity(0.45) }
    static var missFill: Color { miss.opacity(0.14) }
    static var missStroke: Color { miss.opacity(0.38) }

    enum Font {
        static func title(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold)
        }
        static func numeric(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        static func label(_ size: CGFloat = 11) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    /// Tile geometry differs between the lock screen and the island; the
    /// palette does not.
    enum Tile {
        static let lockHeight: CGFloat = 30
        static let lockRadius: CGFloat = 9
        static let lockFont: CGFloat = 14
        static let islandHeight: CGFloat = 26
        static let islandRadius: CGFloat = 8
        static let islandFont: CGFloat = 13
        static let gap: CGFloat = 6
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}
