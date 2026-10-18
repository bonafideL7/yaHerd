import SwiftUI
import UIKit

/// Picks the higher-contrast system foreground for an opaque color fill.
enum AccessibleControlContrast {
    static func foreground(on background: Color, in colorScheme: ColorScheme) -> Color {
        let traits = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )
        let resolvedBackground = UIColor(background).resolvedColor(with: traits)

        guard let backgroundLuminance = relativeLuminance(of: resolvedBackground) else {
            // Retain the system's adaptive text color if UIKit cannot resolve the fill.
            return .primary
        }

        let blackContrast = (backgroundLuminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (backgroundLuminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }

    static func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat? {
        guard let foregroundLuminance = relativeLuminance(of: foreground),
              let backgroundLuminance = relativeLuminance(of: background) else {
            return nil
        }

        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of color: UIColor) -> CGFloat? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(red)
            + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
    }
}

private struct ReadableColorForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let background: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(
            AccessibleControlContrast.foreground(on: background, in: colorScheme)
        )
    }
}

extension View {
    /// Use for text and symbols on a solid, opaque color background, not material/glass.
    func readableForeground(on background: Color) -> some View {
        modifier(ReadableColorForeground(background: background))
    }
}
