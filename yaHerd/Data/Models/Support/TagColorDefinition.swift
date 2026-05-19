//
//  TagColorDefinition.swift
//  yaHerd
//

import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@Model
final class TagColorDefinition: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var prefix: String = ""
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 0
    var alpha: Double = 1
    var sortOrder: Int = 0
    var isHidden: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        prefix: String? = nil,
        rgba: RGBAColor,
        sortOrder: Int = 0,
        isHidden: Bool = false,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now
    ) {
        self.id = id
        self.name = name
        let cleanedPrefix = prefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let cleanedPrefix, !cleanedPrefix.isEmpty {
            self.prefix = cleanedPrefix
        } else {
            self.prefix = TagColorLibraryStore.defaultPrefix(for: name)
        }
        self.red = rgba.r
        self.green = rgba.g
        self.blue = rgba.b
        self.alpha = rgba.a
        self.sortOrder = sortOrder
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var rgba: RGBAColor {
        get { RGBAColor(r: red, g: green, b: blue, a: alpha) }
        set {
            red = newValue.r
            green = newValue.g
            blue = newValue.b
            alpha = newValue.a
            updatedAt = .now
        }
    }

    var color: Color { rgba.color }

    func update(name: String, prefix: String, rgba: RGBAColor) {
        self.name = name
        self.prefix = prefix
        self.rgba = rgba
        self.isHidden = false
        self.updatedAt = .now
    }

}


struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(color: Color) {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var rr: CGFloat = 0
        var gg: CGFloat = 0
        var bb: CGFloat = 0
        var aa: CGFloat = 0
        if ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
            r = Double(rr)
            g = Double(gg)
            b = Double(bb)
            a = Double(aa)
        } else {
            r = 1
            g = 1
            b = 0
            a = 1
        }
        #else
        r = 1
        g = 1
        b = 0
        a = 1
        #endif
    }

    var color: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
}
