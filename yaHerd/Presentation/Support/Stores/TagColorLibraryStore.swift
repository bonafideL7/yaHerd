//
//  TagColorLibraryStore.swift
//  yaHerd
//

import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

protocol AnimalTagDisplayRepresentable {
    var displayTagNumber: String { get }
    var displayTagColorID: UUID? { get }
}

extension AnimalSummary: AnimalTagDisplayRepresentable {}
extension AnimalDetailSnapshot: AnimalTagDisplayRepresentable {}
extension AnimalParentOption: AnimalTagDisplayRepresentable {}

@MainActor
final class TagColorLibraryStore: ObservableObject {
    @Published private(set) var colors: [TagColorDefinition] = []

    private let legacyStorageKey = "tagColorLibrary.v1"
    private let context: ModelContext
    private let syncMode: SyncMode

    init(context: ModelContext, syncMode: SyncMode = .localOnly) {
        self.context = context
        self.syncMode = syncMode
        load()
    }

    var defaultColor: TagColorDefinition {
        colors.first(where: { $0.name.caseInsensitiveCompare("White") == .orderedSame })
            ?? colors.first
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

    func resolvedDefinition(for animal: some AnimalTagDisplayRepresentable) -> TagColorDefinition {
        resolvedDefinition(tagColorID: animal.displayTagColorID)
    }

    func formattedTag(for animal: some AnimalTagDisplayRepresentable) -> String {
        formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
    }

    // MARK: - CRUD

    func upsert(_ def: TagColorDefinition) {
        do {
            let cleanedName = Self.normalizedDisplayName(def.name)
            guard !cleanedName.isEmpty else { return }

            let cleanedPrefix = Self.normalizedPrefix(def.prefix, fallbackName: cleanedName)
            let existingByID = try persistedColor(id: def.id)
            let existingByName = try persistedColor(name: cleanedName)

            if let existingByName, existingByName.id != def.id {
                existingByName.update(name: cleanedName, prefix: cleanedPrefix, rgba: def.rgba)
                try remapTagColorIDs([def.id: existingByName.id])
                if let existingByID {
                    context.delete(existingByID)
                }
            } else if let existingByID {
                existingByID.update(name: cleanedName, prefix: cleanedPrefix, rgba: def.rgba)
            } else {
                def.name = cleanedName
                def.prefix = cleanedPrefix
                def.sortOrder = colors.count
                def.isHidden = false
                def.updatedAt = .now
                context.insert(def)
            }

            saveAndReload()
        } catch {
            assertionFailure("Failed to upsert tag color: \(error)")
        }
    }

    func delete(at offsets: IndexSet) {
        do {
            for index in offsets where colors.indices.contains(index) {
                let color = colors[index]
                if let persisted = try persistedColor(id: color.id) {
                    context.delete(persisted)
                }
            }

            saveAndReload()
        } catch {
            assertionFailure("Failed to delete tag color: \(error)")
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        var reordered = colors
        reordered.move(fromOffsets: source, toOffset: destination)

        do {
            for (index, color) in reordered.enumerated() {
                if let persisted = try persistedColor(id: color.id) {
                    persisted.sortOrder = index
                    persisted.updatedAt = .now
                }
            }
            saveAndReload()
        } catch {
            assertionFailure("Failed to move tag color: \(error)")
        }
    }

    func restoreDefaultColors() {
        do {
            for defaultColor in Self.seedDefaultColors() {
                if let existingByName = try persistedColor(name: defaultColor.name) {
                    existingByName.update(
                        name: defaultColor.name,
                        prefix: defaultColor.prefix,
                        rgba: defaultColor.rgba
                    )
                } else {
                    context.insert(defaultColor)
                }
            }

            saveAndReload()
        } catch {
            assertionFailure("Failed to restore default tag colors: \(error)")
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            var persistedColors = try fetchPersistedColors()

            if persistedColors.isEmpty {
                let colorsToSeed = legacyColorsFromUserDefaults() ?? Self.seedDefaultColors()
                seed(colorsToSeed)
                try context.save()
                UserDefaults.standard.removeObject(forKey: legacyStorageKey)
                persistedColors = try fetchPersistedColors()
            }

            try reconcileColorNames(in: persistedColors)
            colors = try fetchPersistedColors()
        } catch {
            colors = []
        }
    }

    func refresh() {
        load()
    }

    /// Enforces the app-level rule that tag color names are unique.
    /// In iCloud mode, the newest record wins so a synced CloudKit record with the same name replaces
    /// a local seeded copy on the next refresh. In local-only mode, the existing library order wins.
    private func reconcileColorNames(in persistedColors: [TagColorDefinition]) throws {
        var didChange = false
        var idRemaps: [UUID: UUID] = [:]
        let grouped = Dictionary(grouping: persistedColors) { Self.normalizedNameKey($0.name) }

        for (_, group) in grouped {
            guard !group.isEmpty else { continue }

            for color in group where color.isHidden {
                color.isHidden = false
                color.updatedAt = .now
                didChange = true
            }

            guard group.count > 1 else { continue }
            let winner = canonicalColor(from: group)

            for duplicate in group where duplicate !== winner {
                idRemaps[duplicate.id] = winner.id
                context.delete(duplicate)
                didChange = true
            }
        }

        if !idRemaps.isEmpty {
            try remapTagColorIDs(idRemaps)
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    private func canonicalColor(from colors: [TagColorDefinition]) -> TagColorDefinition {
        if syncMode == .iCloud {
            // If a synced/user record and a local seeded default have the same name, keep the
            // synced/user record and delete the local default copy. This prevents default-color
            // seed records from duplicating names when iCloud data arrives later.
            let nonDefaultColors = colors.filter { !Self.defaultColorIDs.contains($0.id) }
            let candidates = nonDefaultColors.isEmpty ? colors : nonDefaultColors
            return candidates.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.sortOrder < $1.sortOrder
            }.first ?? colors[0]
        }

        return colors.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.updatedAt < $1.updatedAt
        }.first ?? colors[0]
    }

    private func remapTagColorIDs(_ remaps: [UUID: UUID]) throws {
        let animals = try context.fetch(FetchDescriptor<Animal>())
        for animal in animals {
            if let colorID = animal.tagColorID, let replacementID = remaps[colorID] {
                animal.tagColorID = replacementID
            }
        }

        let tags = try context.fetch(FetchDescriptor<AnimalTag>())
        for tag in tags {
            if let colorID = tag.colorID, let replacementID = remaps[colorID] {
                tag.colorID = replacementID
            }
        }

        let fieldCheckAnimalChecks = try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>())
        for check in fieldCheckAnimalChecks {
            if let colorID = check.rosterTagColorID, let replacementID = remaps[colorID] {
                check.rosterTagColorID = replacementID
            }
        }
    }

    private func fetchPersistedColors() throws -> [TagColorDefinition] {
        let descriptor = FetchDescriptor<TagColorDefinition>(
            sortBy: [
                SortDescriptor(\TagColorDefinition.sortOrder),
                SortDescriptor(\TagColorDefinition.name)
            ]
        )
        return try context.fetch(descriptor)
    }

    private func persistedColor(id: UUID) throws -> TagColorDefinition? {
        let descriptor = FetchDescriptor<TagColorDefinition>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func persistedColor(name: String) throws -> TagColorDefinition? {
        let key = Self.normalizedNameKey(name)
        return try fetchPersistedColors().first { Self.normalizedNameKey($0.name) == key }
    }

    private func saveAndReload() {
        do {
            try context.save()
            try reconcileColorNames(in: fetchPersistedColors())
            colors = try fetchPersistedColors()
        } catch {
            assertionFailure("Failed to save tag colors: \(error)")
        }
    }

    private func seed(_ seedColors: [TagColorDefinition]) {
        var usedNames = Set<String>()

        for color in seedColors {
            let cleanedName = Self.normalizedDisplayName(color.name)
            let key = Self.normalizedNameKey(cleanedName)
            guard !cleanedName.isEmpty, !usedNames.contains(key) else { continue }

            color.name = cleanedName
            color.prefix = Self.normalizedPrefix(color.prefix, fallbackName: cleanedName)
            color.sortOrder = usedNames.count
            color.isHidden = false
            context.insert(color)
            usedNames.insert(key)
        }
    }

    private func legacyColorsFromUserDefaults() -> [TagColorDefinition]? {
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey) else {
            return nil
        }

        guard let legacyColors = try? JSONDecoder().decode([LegacyTagColorDefinition].self, from: data) else {
            return nil
        }

        return legacyColors.enumerated().map { index, legacy in
            TagColorDefinition(
                id: legacy.id,
                name: legacy.name,
                prefix: legacy.prefix,
                rgba: legacy.rgba,
                sortOrder: index
            )
        }
    }

    // MARK: - Prefix + Defaults

    nonisolated static func normalizedDisplayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedNameKey(_ name: String) -> String {
        normalizedDisplayName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    nonisolated static func normalizedPrefix(_ prefix: String, fallbackName: String) -> String {
        let cleanedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return cleanedPrefix.isEmpty ? defaultPrefix(for: fallbackName) : cleanedPrefix
    }

    nonisolated static func defaultPrefix(for name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let words = cleaned.split(whereSeparator: { $0.isWhitespace })
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        let joined = letters.joined()
        return joined.isEmpty ? "?" : joined
    }


    nonisolated static var defaultColorIDs: Set<UUID> { [
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D01")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D02")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D03")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D04")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D05")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D06")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D07")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D08")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D09")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0A")!,
        UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0B")!
    ] }

    nonisolated static func seedDefaultColors() -> [TagColorDefinition] {
        // Stable IDs keep sample/default records predictable, but names are the real uniqueness rule.
        return [
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D01")!, name: "Yellow", rgba: RGBAColor(r: 1, g: 1, b: 0), sortOrder: 0),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D02")!, name: "White",  rgba: RGBAColor(r: 1, g: 1, b: 1), sortOrder: 1),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D03")!, name: "Black",  rgba: RGBAColor(r: 0, g: 0, b: 0), sortOrder: 2),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D04")!, name: "Red",    rgba: RGBAColor(r: 1, g: 0, b: 0), sortOrder: 3),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D05")!, name: "Orange", rgba: RGBAColor(r: 1, g: 0.5, b: 0), sortOrder: 4),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D06")!, name: "Green",  rgba: RGBAColor(r: 0, g: 0.7, b: 0.2), sortOrder: 5),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D07")!, name: "Blue",   rgba: RGBAColor(r: 0, g: 0.48, b: 1), sortOrder: 6),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D08")!, name: "Purple", rgba: RGBAColor(r: 0.6, g: 0.4, b: 1), sortOrder: 7),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D09")!, name: "Pink",   rgba: RGBAColor(r: 1, g: 0.2, b: 0.6), sortOrder: 8),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0A")!, name: "Brown",  rgba: RGBAColor(r: 0.55, g: 0.27, b: 0.07), sortOrder: 9),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0B")!, name: "Gray",   rgba: RGBAColor(r: 0.6, g: 0.6, b: 0.6), sortOrder: 10)
        ]
    }
}

private struct LegacyTagColorDefinition: Decodable {
    var id: UUID
    var name: String
    var prefix: String
    var rgba: RGBAColor
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
