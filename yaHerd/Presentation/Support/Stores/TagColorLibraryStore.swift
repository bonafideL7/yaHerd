//
//  TagColorLibraryStore.swift
//  yaHerd
//

import Foundation
import SwiftUI

protocol AnimalTagDisplayRepresentable {
    var displayTagNumber: String { get }
    var displayTagColorID: UUID? { get }
}

extension AnimalSummary: AnimalTagDisplayRepresentable {}
extension AnimalDetailSnapshot: AnimalTagDisplayRepresentable {}
extension AnimalParentOption: AnimalTagDisplayRepresentable {}

@MainActor
final class TagColorLibraryStore: ObservableObject {
    @Published private(set) var colors: [TagColorSnapshot] = []
    @Published private(set) var lastErrorMessage: String?

    private let repository: any TagColorRepository
    private var historicalDefinitionsByID: [UUID: TagColorSnapshot] = [:]

    init(repository: any TagColorRepository) {
        self.repository = repository
        load()
    }

    var defaultColor: TagColorSnapshot {
        colors.first(where: { $0.isDefault })
            ?? colors.first(where: { Self.normalizedNameKey($0.name) == Self.normalizedNameKey("White") })
            ?? colors.first
            ?? TagColorSnapshot(name: "White", rgba: RGBAColor(r: 1, g: 1, b: 1), isDefault: true)
    }

    var defaultColorID: UUID? {
        definition(for: defaultColor.id)?.id ?? colors.first?.id
    }

    func resolvedColorID(_ id: UUID?) -> UUID? {
        if let id, definition(for: id) != nil {
            return id
        }

        return defaultColorID
    }

    /// Unlike display fallback, editing must never replace an existing color
    /// UUID just because its definition is hidden or a lookup temporarily fails.
    /// Only a genuinely absent selection inherits the library default.
    func editableColorID(_ id: UUID?) -> UUID? {
        id ?? defaultColorID
    }

    func definition(for id: UUID?) -> TagColorSnapshot? {
        guard let id else { return nil }

        if let visible = colors.first(where: { $0.id == id }) {
            return visible
        }

        if let cached = historicalDefinitionsByID[id] {
            return cached
        }

        guard let historical = try? repository.fetchColor(id: id) else {
            return nil
        }

        historicalDefinitionsByID[id] = historical
        return historical
    }

    func resolvedDefinition(tagColorID: UUID?) -> TagColorSnapshot {
        definition(for: tagColorID) ?? defaultColor
    }

    func formattedTag(tagNumber: String, colorID: UUID?) -> String {
        let definition = resolvedDefinition(tagColorID: colorID)
        let number = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? "UT" : "\(definition.prefix)\(number)"
    }

    func resolvedDefinition(for animal: some AnimalTagDisplayRepresentable) -> TagColorSnapshot {
        resolvedDefinition(tagColorID: animal.displayTagColorID)
    }

    func formattedTag(for animal: some AnimalTagDisplayRepresentable) -> String {
        formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
    }

    @discardableResult
    func upsert(_ color: TagColorSnapshot) -> Bool {
        performRepositoryWrite("Failed to save tag color") {
            try repository.upsert(color)
        }
    }

    func setDefaultColor(id: UUID) {
        performRepositoryWrite("Failed to set default tag color") {
            try repository.setDefaultColor(id: id)
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            colors.indices.contains(index) ? colors[index].id : nil
        }

        performRepositoryWrite("Failed to delete tag color") {
            try repository.deleteColors(ids: ids)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        var reordered = colors
        reordered.move(fromOffsets: source, toOffset: destination)
        let orderedIDs = reordered.map(\.id)

        performRepositoryWrite("Failed to reorder tag colors") {
            try repository.reorder(colorIDs: orderedIDs)
        }
    }

    func restoreDefaultColors() {
        performRepositoryWrite("Failed to restore default tag colors") {
            try repository.restoreDefaultColors()
        }
    }

    func refresh() {
        load()
    }

    private func load() {
        do {
            historicalDefinitionsByID.removeAll()
            colors = try repository.fetchColors()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    // Saving to Core Data and refreshing the visible library are distinct operations.
    // A failed refresh must not make a committed write look like a failed save.
    @discardableResult
    private func performRepositoryWrite(
        _ failureMessage: String,
        operation: () throws -> Void
    ) -> Bool {
        do {
            try operation()
        } catch {
            lastErrorMessage = "\(failureMessage): \(UserVisibleErrorMessage.make(error))"
            return false
        }

        do {
            let refreshedColors = try repository.fetchColors()
            colors = refreshedColors
            historicalDefinitionsByID.removeAll()
            lastErrorMessage = nil
        } catch {
            // Keep the last valid list and cached historical definitions until
            // a later refresh can read the successfully committed mutation.
            lastErrorMessage = "Changes saved, but tag colors could not be refreshed: \(UserVisibleErrorMessage.make(error))"
        }
        return true
    }

    nonisolated static func normalizedDisplayName(_ name: String) -> String {
        TagColorLibraryRules.normalizedDisplayName(name)
    }

    nonisolated static func normalizedNameKey(_ name: String) -> String {
        TagColorLibraryRules.normalizedNameKey(name)
    }

    nonisolated static func normalizedPrefix(_ prefix: String, fallbackName: String) -> String {
        TagColorLibraryRules.normalizedPrefix(prefix, fallbackName: fallbackName)
    }

    nonisolated static func defaultPrefix(for name: String) -> String {
        TagColorLibraryRules.defaultPrefix(for: name)
    }

    nonisolated static var defaultColorIDs: Set<UUID> {
        TagColorDefaults.defaultColorIDs
    }

    nonisolated static func seedDefaultColors() -> [TagColorSnapshot] {
        TagColorDefaults.seedDefaultColors()
    }
}
