//
//  TagColorDefinition.swift
//  yaHerd
//

import Foundation
import SwiftData

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
    var isDefault: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        prefix: String? = nil,
        rgba: RGBAColor,
        sortOrder: Int = 0,
        isHidden: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now
    ) {
        let normalizedName = TagColorLibraryRules.normalizedDisplayName(name)

        self.id = id
        self.name = normalizedName
        self.prefix = TagColorLibraryRules.normalizedPrefix(prefix ?? "", fallbackName: normalizedName)
        self.red = rgba.r
        self.green = rgba.g
        self.blue = rgba.b
        self.alpha = rgba.a
        self.sortOrder = sortOrder
        self.isHidden = isHidden
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(snapshot: TagColorSnapshot) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            prefix: snapshot.prefix,
            rgba: snapshot.rgba,
            sortOrder: snapshot.sortOrder,
            isDefault: snapshot.isDefault,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
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

    var snapshot: TagColorSnapshot {
        TagColorSnapshot(
            id: id,
            name: name,
            prefix: prefix,
            rgba: rgba,
            sortOrder: sortOrder,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(name: String, prefix: String, rgba: RGBAColor) {
        let normalizedName = TagColorLibraryRules.normalizedDisplayName(name)

        self.name = normalizedName
        self.prefix = TagColorLibraryRules.normalizedPrefix(prefix, fallbackName: normalizedName)
        self.rgba = rgba
        self.isHidden = false
        self.updatedAt = .now
    }

    func update(from snapshot: TagColorSnapshot) {
        update(name: snapshot.name, prefix: snapshot.prefix, rgba: snapshot.rgba)
        sortOrder = snapshot.sortOrder
        isDefault = snapshot.isDefault
        createdAt = snapshot.createdAt
        updatedAt = .now
    }

    func setDefault(_ isDefault: Bool) {
        guard self.isDefault != isDefault else { return }
        self.isDefault = isDefault
        self.updatedAt = .now
    }
}
