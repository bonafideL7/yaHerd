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
                let resolved = UIColor(background).resolvedColor(with: traits)
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

    private func assertReadableForeground(
        on background: Color,
        appearance: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scheme: ColorScheme = appearance == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: appearance)
        let backgroundColor = UIColor(background).resolvedColor(with: traits)
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
