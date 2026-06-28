//
//  TagColorSnapshot.swift
//  yaHerd
//

import Foundation

struct TagColorSnapshot: Identifiable, Hashable {
    var id: UUID
    var name: String
    var prefix: String
    var rgba: RGBAColor
    var sortOrder: Int
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        prefix: String? = nil,
        rgba: RGBAColor,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        let normalizedName = TagColorLibraryRules.normalizedDisplayName(name)

        self.id = id
        self.name = normalizedName
        self.prefix = TagColorLibraryRules.normalizedPrefix(prefix ?? "", fallbackName: normalizedName)
        self.rgba = rgba
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
