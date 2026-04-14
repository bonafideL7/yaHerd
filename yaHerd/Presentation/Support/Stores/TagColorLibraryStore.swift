//
//  TagColorLibraryStore.swift
//  yaHerd
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TagColorDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var prefix: String
    var rgba: RGBAColor

    init(id: UUID = UUID(), name: String, prefix: String? = nil, rgba: RGBAColor) {
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
        self.rgba = rgba
    }

    var color: Color { rgba.color }
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

final class TagColorLibraryStore: ObservableObject {
    @Published private(set) var colors: [TagColorDefinition] = []

    private let storageKey = "tagColorLibrary.v1"
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    init() {
        load()
        if colors.isEmpty {
            colors = Self.seedDefaultColors()
            save()
        }
    }

    var defaultColor: TagColorDefinition {
        colors.first(where: { $0.name.caseInsensitiveCompare("White") == .orderedSame })
            ?? TagColorDefinition(name: "White", rgba: RGBAColor(r: 1, g: 1, b: 1))
    }

    func definition(for id: UUID?) -> TagColorDefinition? {
        guard let id else { return nil }
        return colors.first(where: { $0.id == id })
    }


    func resolvedDefinition(tagColorID: UUID?) -> TagColorDefinition {
        definition(for: tagColorID) ?? defaultColor
    }

    func formattedTag(tagNumber: String, colorID: UUID?) -> String {
        let def = resolvedDefinition(tagColorID: colorID)
        let number = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? "UT" : "\(def.prefix)\(number)"
    }

    func resolvedDefinition(for animal: Animal) -> TagColorDefinition {
        resolvedDefinition(tagColorID: animal.displayTagColorID)
    }

    func resolvedDefinition(for animal: AnimalSummary) -> TagColorDefinition {
        resolvedDefinition(tagColorID: animal.displayTagColorID)
    }

    func formattedTag(for animal: Animal) -> String {
        formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
    }

    func formattedTag(for animal: AnimalSummary) -> String {
        formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
    }

    // MARK: - CRUD

    func upsert(_ def: TagColorDefinition) {
        if let idx = colors.firstIndex(where: { $0.id == def.id }) {
            colors[idx] = def
        } else {
            colors.append(def)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        colors.remove(atOffsets: offsets)
        if colors.isEmpty {
            colors = Self.seedDefaultColors()
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        colors.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            colors = []
            return
        }
        colors = (try? decoder.decode([TagColorDefinition].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? encoder.encode(colors) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Prefix + Defaults

    static func defaultPrefix(for name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let words = cleaned.split(whereSeparator: { $0.isWhitespace })
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        let joined = letters.joined()
        return joined.isEmpty ? "?" : joined
    }

    static func seedDefaultColors() -> [TagColorDefinition] {
        // Yellow first -> default
        return [
            TagColorDefinition(name: "Yellow", rgba: RGBAColor(r: 1, g: 1, b: 0)),
            TagColorDefinition(name: "White",  rgba: RGBAColor(r: 1, g: 1, b: 1)),
            TagColorDefinition(name: "Black",  rgba: RGBAColor(r: 0, g: 0, b: 0)),
            TagColorDefinition(name: "Red",    rgba: RGBAColor(r: 1, g: 0, b: 0)),
            TagColorDefinition(name: "Orange", rgba: RGBAColor(r: 1, g: 0.5, b: 0)),
            TagColorDefinition(name: "Green",  rgba: RGBAColor(r: 0, g: 0.7, b: 0.2)),
            TagColorDefinition(name: "Blue",   rgba: RGBAColor(r: 0, g: 0.48, b: 1)),
            TagColorDefinition(name: "Purple", rgba: RGBAColor(r: 0.6, g: 0.4, b: 1)),
            TagColorDefinition(name: "Pink",   rgba: RGBAColor(r: 1, g: 0.2, b: 0.6)),
            TagColorDefinition(name: "Brown",  rgba: RGBAColor(r: 0.55, g: 0.27, b: 0.07)),
            TagColorDefinition(name: "Gray",   rgba: RGBAColor(r: 0.6, g: 0.6, b: 0.6))
        ]
    }
}

extension Color {
    /// Relative luminance (WCAG-ish). Used for adjusting outlines on light colors.
    var relativeLuminance: Double {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var rr: CGFloat = 0
        var gg: CGFloat = 0
        var bb: CGFloat = 0
        var aa: CGFloat = 0
        guard ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) else { return 0 }

        func f(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        let r = f(Double(rr))
        let g = f(Double(gg))
        let b = f(Double(bb))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
        #else
        return 0
        #endif
    }
}
