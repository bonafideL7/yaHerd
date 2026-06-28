//
//  TagColor+Presentation.swift
//  yaHerd
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension RGBAColor {
    init(color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
        } else {
            self.init(r: 1, g: 1, b: 0)
        }
        #else
        self.init(r: 1, g: 1, b: 0)
        #endif
    }

    var color: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
}

extension TagColorSnapshot {
    var color: Color { rgba.color }
}

extension Color {
    /// Relative luminance (WCAG-ish). Used for adjusting outlines on light colors.
    var relativeLuminance: Double {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }

        func component(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let r = component(Double(red))
        let g = component(Double(green))
        let b = component(Double(blue))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
        #else
        return 0
        #endif
    }
}
