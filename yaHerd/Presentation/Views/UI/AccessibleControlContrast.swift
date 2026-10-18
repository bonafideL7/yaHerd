import SwiftUI
import UIKit

/// Picks the higher-contrast system foreground for an opaque color fill.
enum AccessibleControlContrast {
    /// Native swipe actions use system-owned white labels; their fill must be dark enough.
    static let nativeSwipeBlue = Color(red: 19.0 / 255, green: 90.0 / 255, blue: 158.0 / 255)
    static let nativeSwipeOrange = Color(red: 154.0 / 255, green: 75.0 / 255, blue: 0)

    static func nativeSwipeAccent(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 40.0 / 255, green: 117.0 / 255, blue: 75.0 / 255)
            : .accentColor
    }

    /// The asset uses burgundy in Light Mode and pale green in Dark Mode.
    /// Do not infer this role through UIColor(Color.accentColor): the bridge can
    /// resolve a different appearance than SwiftUI actually renders.
    static func accentForeground(in scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func foreground(on background: Color, in colorScheme: ColorScheme) -> Color {
        if background == .accentColor {
            return accentForeground(in: colorScheme)
        }

        guard let luminance = relativeLuminance(of: resolved(background, in: colorScheme)) else {
            return .primary
        }
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
            ? .black : .white
    }

    /// Keep a prominent action's original hue but adjust its luminance
    /// enough for the same .primary text used by its surrounding card.
    /// Color is judged against the solid tint; final glass compositing
    /// should still be inspected on the device.
    static func prominentActionTint(_ tint: Color, in scheme: ColorScheme) -> Color {
        guard let original = rgb(of: resolved(tint, in: scheme)) else {
            return tint
        }

        let foregroundLuminance: CGFloat = scheme == .dark ? 1 : 0
        // A small margin over 4.5:1 helps with platform glass compositing.
        let targetContrast: CGFloat = 5
        if ratio(luminance(original), foregroundLuminance) >= targetContrast {
            return tint
        }

        let target: CGFloat = scheme == .dark ? 0 : 1
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<18 {
            let fraction = (low + high) / 2
            let candidate = original.map { $0 * (1 - fraction) + target * fraction }
            if ratio(luminance(candidate), foregroundLuminance) >= targetContrast {
                high = fraction
            } else {
                low = fraction
            }
        }
        return color(original.map { $0 * (1 - high) + target * high })
    }

    /// A shared icon-badge palette: retain the supplied hue, darkening a
    /// too-bright fill just enough for a white symbol at 4.5:1 contrast.
    static func iconFill(for tint: Color, in scheme: ColorScheme) -> Color {
        guard let components = rgb(of: resolved(tint, in: scheme)) else {
            return .black
        }

        if whiteContrast(components) >= 4.5 {
            return color(components)
        }

        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<18 {
            let midpoint = (low + high) / 2
            let candidate = components.map { $0 * midpoint }
            if whiteContrast(candidate) >= 4.5 {
                low = midpoint
            } else {
                high = midpoint
            }
        }
        return color(components.map { $0 * low })
    }

    /// Tint used for link/action text on an ordinary grouped card, not on the
    /// tint itself. Adjust toward black/white only if required to reach 4.5:1.
    static func cardTextTint(_ tint: Color, in scheme: ColorScheme) -> Color {
        guard let original = rgb(of: resolved(tint, in: scheme)),
              let background = relativeLuminance(
                of: UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits(for: scheme))
              ) else {
            return .primary
        }

        if ratio(luminance(original), background) >= 4.5 {
            return color(original)
        }

        let target: CGFloat = background > 0.18 ? 0 : 1
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<18 {
            let midpoint = (low + high) / 2
            let candidate = original.map { $0 * (1 - midpoint) + target * midpoint }
            if ratio(luminance(candidate), background) >= 4.5 {
                high = midpoint
            } else {
                low = midpoint
            }
        }
        return color(original.map { $0 * (1 - high) + target * high })
    }

    private static func traits(for scheme: ColorScheme) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    }

    private static func resolved(_ color: Color, in scheme: ColorScheme) -> UIColor {
        if color == .accentColor {
            let traits = traits(for: scheme)
            let fallback = scheme == .dark
                ? UIColor(red: 0.761, green: 0.834, blue: 0.702, alpha: 1)
                : UIColor(red: 0.158, green: 0, blue: 0.074, alpha: 1)
            return (UIColor(named: "AccentColor", in: .main, compatibleWith: traits) ?? fallback)
                .resolvedColor(with: traits)
        }
        return UIColor(color).resolvedColor(with: traits(for: scheme))
    }

    private static func rgb(of color: UIColor) -> [CGFloat]? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return [red, green, blue]
    }

    private static func color(_ rgb: [CGFloat]) -> Color {
        Color(red: Double(rgb[0]), green: Double(rgb[1]), blue: Double(rgb[2]))
    }

    private static func ratio(_ left: CGFloat, _ right: CGFloat) -> CGFloat {
        (max(left, right) + 0.05) / (min(left, right) + 0.05)
    }

    private static func whiteContrast(_ rgb: [CGFloat]) -> CGFloat {
        1.05 / (luminance(rgb) + 0.05)
    }

    private static func luminance(_ rgb: [CGFloat]) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : CGFloat(pow(Double((component + 0.055) / 1.055), 2.4))
        }
        return 0.2126 * linearized(rgb[0])
            + 0.7152 * linearized(rgb[1])
            + 0.0722 * linearized(rgb[2])
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
                : CGFloat(pow(Double((component + 0.055) / 1.055), 2.4))
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

private struct ReadableAccentForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(AccessibleControlContrast.accentForeground(in: colorScheme))
    }
}

private struct ReadableIconBadge: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(AccessibleControlContrast.iconFill(for: tint, in: colorScheme))
            )
    }
}

private struct ReadableCardTextTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(AccessibleControlContrast.cardTextTint(tint, in: colorScheme))
    }
}

extension View {
    /// Use only on a solid opaque fill, not native glass/material.
    func readableForeground(on background: Color) -> some View {
        modifier(ReadableColorForeground(background: background))
    }

    /// Exact foreground counterpart of the app's named AccentColor asset.
    func readableAccentForeground() -> some View {
        modifier(ReadableAccentForeground())
    }

    /// One app-level treatment for icons in solid colored circles.
    func readableIconBadge(tint: Color, size: CGFloat) -> some View {
        modifier(ReadableIconBadge(tint: tint, size: size))
    }

    /// Tinted text on the app's secondary grouped card surface.
    func readableCardTextTint(_ tint: Color) -> some View {
        modifier(ReadableCardTextTint(tint: tint))
    }
}
