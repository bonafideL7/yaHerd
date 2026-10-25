import SwiftUI
import UIKit
import XCTest
@testable import yaHerd

@MainActor
final class AccessibleControlContrastTests: XCTestCase {
    func testAccentColorHasReadableForegroundInBothAppearances() throws {
        try assertReadableForeground(on: .accentColor, appearance: .light)
        try assertReadableForeground(on: .accentColor, appearance: .dark)
    }

    func testStatusColorsHaveReadableForegroundInBothAppearances() throws {
        let backgrounds: [Color] = [.yellow, .green, .teal, .orange, .red, .purple, .blue, .brown]
        for background in backgrounds {
            try assertReadableForeground(on: background, appearance: .light)
            try assertReadableForeground(on: background, appearance: .dark)
        }
    }

    func testNativeSwipeActionFillsContrastWithSystemWhiteLabels() throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let scheme: ColorScheme = appearance == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            let backgrounds: [Color] = [
                AccessibleControlContrast.nativeSwipeBlue,
                AccessibleControlContrast.nativeSwipeOrange,
                AccessibleControlContrast.nativeSwipeAccent(in: scheme)
            ]

            for background in backgrounds {
                let resolved = resolvedColor(background, traits: traits)
                let ratio = try XCTUnwrap(
                    AccessibleControlContrast.contrastRatio(
                        foreground: .white,
                        background: resolved
                    )
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5)
            }
        }
    }

    func testExplicitBrandAccentForegroundMatchesActualNamedAsset() throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let scheme: ColorScheme = appearance == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            let accent = try XCTUnwrap(
                UIColor(named: "AccentColor", in: .main, compatibleWith: traits)?
                    .resolvedColor(with: traits)
            )
            let semanticForeground = AccessibleControlContrast.accentForeground(in: scheme)
            let foreground = UIColor(semanticForeground)
            let ratio = try XCTUnwrap(
                AccessibleControlContrast.contrastRatio(foreground: foreground, background: accent)
            )
            XCTAssertGreaterThanOrEqual(ratio, 4.5)
            XCTAssertEqual(
                semanticForeground,
                scheme == .dark ? Color.black : Color.white
            )
            XCTAssertEqual(
                AccessibleControlContrast.foreground(on: .accentColor, in: scheme),
                semanticForeground
            )
        }
    }

    func testSharedIconBadgePaletteUsesReadableWhiteSymbolsInBothAppearances() throws {
        let tints: [Color] = [.accentColor, .pink, .blue, .purple, .orange, .yellow, .red, .green, .teal]
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let scheme: ColorScheme = appearance == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            for tint in tints {
                let fill = AccessibleControlContrast.iconFill(for: tint, in: scheme)
                let ratio = try XCTUnwrap(
                    AccessibleControlContrast.contrastRatio(
                        foreground: .white,
                        background: UIColor(fill).resolvedColor(with: traits)
                    )
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5)
            }
        }
    }

    func testProminentSuggestionTintContrastsWithAppearanceText() throws {
        let tints: [Color] = [.green, .blue, .purple, .orange, .yellow, .brown, .pink]
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let scheme: ColorScheme = appearance == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            let textColor: UIColor = appearance == .dark ? .white : .black

            for tint in tints {
                let fill = AccessibleControlContrast.prominentActionTint(tint, in: scheme)
                let ratio = try XCTUnwrap(
                    AccessibleControlContrast.contrastRatio(
                        foreground: textColor,
                        background: UIColor(fill).resolvedColor(with: traits)
                    )
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5)
            }
        }
    }

    func testTintedCardTextRemainsReadableOnGroupedCards() throws {
        let tints: [Color] = [.accentColor, .pink, .blue, .purple, .orange, .yellow, .green, .red]
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let scheme: ColorScheme = appearance == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            let cardBackground = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            for tint in tints {
                let foreground = UIColor(AccessibleControlContrast.cardTextTint(tint, in: scheme))
                    .resolvedColor(with: traits)
                let ratio = try XCTUnwrap(
                    AccessibleControlContrast.contrastRatio(
                        foreground: foreground,
                        background: cardBackground
                    )
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5)
            }
        }
    }

    private func resolvedColor(_ color: Color, traits: UITraitCollection) -> UIColor {
        if color == .accentColor {
            return (UIColor(named: "AccentColor", in: .main, compatibleWith: traits)
                ?? UIColor(color)).resolvedColor(with: traits)
        }
        return UIColor(color).resolvedColor(with: traits)
    }

    private func assertReadableForeground(
        on background: Color,
        appearance: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scheme: ColorScheme = appearance == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: appearance)
        let backgroundColor = resolvedColor(background, traits: traits)
        let foreground = AccessibleControlContrast.foreground(on: background, in: scheme)
        let foregroundColor = UIColor(foreground).resolvedColor(with: traits)

        let ratio = try XCTUnwrap(
            AccessibleControlContrast.contrastRatio(
                foreground: foregroundColor,
                background: backgroundColor
            ),
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(ratio, 4.5, file: file, line: line)
    }
}
