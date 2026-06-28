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

    func definition(for id: UUID?) -> TagColorSnapshot? {
        guard let id else { return nil }
        return colors.first(where: { $0.id == id })
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

    func upsert(_ color: TagColorSnapshot) {
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
            colors = try repository.fetchColors()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            assertionFailure("Failed to load tag colors: \(error)")
        }
    }

    private func performRepositoryWrite(_ failureMessage: String, operation: () throws -> Void) {
        do {
            try operation()
            colors = try repository.fetchColors()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            assertionFailure("\(failureMessage): \(error)")
        }
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
