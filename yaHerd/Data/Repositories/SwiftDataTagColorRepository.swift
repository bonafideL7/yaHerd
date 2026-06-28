//
//  SwiftDataTagColorRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataTagColorRepository: TagColorRepository {
    private let context: ModelContext
    private let duplicateResolutionPolicy: TagColorDuplicateResolutionPolicy
    private let legacyStorageKey = "tagColorLibrary.v1"

    init(
        context: ModelContext,
        duplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins
    ) {
        self.context = context
        self.duplicateResolutionPolicy = duplicateResolutionPolicy
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        try prepareLibraryIfNeeded()
        return try fetchPersistedColors().map(\.snapshot)
    }

    func upsert(_ color: TagColorSnapshot) throws {
        let cleanedName = TagColorLibraryRules.normalizedDisplayName(color.name)
        guard !cleanedName.isEmpty else { return }

        let cleanedPrefix = TagColorLibraryRules.normalizedPrefix(color.prefix, fallbackName: cleanedName)
        let existingByID = try persistedColor(id: color.id)
        let existingByName = try persistedColor(name: cleanedName)
        let shouldBecomeDefault = color.isDefault || existingByID?.isDefault == true

        if let existingByName, existingByName.id != color.id {
            existingByName.update(name: cleanedName, prefix: cleanedPrefix, rgba: color.rgba)
            if shouldBecomeDefault {
                existingByName.setDefault(true)
            }
            try remapTagColorIDs([color.id: existingByName.id])
            if let existingByID {
                context.delete(existingByID)
            }
        } else if let existingByID {
            existingByID.update(name: cleanedName, prefix: cleanedPrefix, rgba: color.rgba)
            if shouldBecomeDefault {
                existingByID.setDefault(true)
            }
        } else {
            var snapshot = color
            snapshot.name = cleanedName
            snapshot.prefix = cleanedPrefix
            snapshot.sortOrder = try fetchPersistedColors().count
            snapshot.isDefault = shouldBecomeDefault
            context.insert(TagColorDefinition(snapshot: snapshot))
        }

        try saveAndNormalize()

        if color.isDefault, let persisted = try persistedColor(name: cleanedName) {
            try setDefaultColor(id: persisted.id)
        }
    }

    func setDefaultColor(id: UUID) throws {
        let persistedColors = try fetchPersistedColors()
        guard persistedColors.contains(where: { $0.id == id }) else { return }

        for color in persistedColors {
            color.setDefault(color.id == id)
        }

        try saveAndNormalize()
    }

    func deleteColors(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let idsToDelete = Set(ids)

        for color in try fetchPersistedColors() where idsToDelete.contains(color.id) {
            context.delete(color)
        }

        try saveAndNormalize()
    }

    func reorder(colorIDs: [UUID]) throws {
        guard !colorIDs.isEmpty else { return }
        let sortOrderByID = Dictionary(uniqueKeysWithValues: colorIDs.enumerated().map { ($0.element, $0.offset) })

        for color in try fetchPersistedColors() {
            if let sortOrder = sortOrderByID[color.id], color.sortOrder != sortOrder {
                color.sortOrder = sortOrder
                color.updatedAt = .now
            }
        }

        try saveAndNormalize()
    }

    func restoreDefaultColors() throws {
        try removeRetiredDefaultColors()
        let existingDefaultID = try fetchPersistedColors().first(where: { $0.isDefault })?.id

        for defaultColor in TagColorDefaults.seedDefaultColors() {
            if let existingByName = try persistedColor(name: defaultColor.name) {
                existingByName.update(
                    name: defaultColor.name,
                    prefix: defaultColor.prefix,
                    rgba: defaultColor.rgba
                )
            } else {
                var snapshot = defaultColor
                if existingDefaultID != nil {
                    snapshot.isDefault = false
                }
                context.insert(TagColorDefinition(snapshot: snapshot))
            }
        }

        try saveAndNormalize()
    }

    private func prepareLibraryIfNeeded() throws {
        let persistedColors = try fetchPersistedColors()

        if persistedColors.isEmpty {
            let colorsToSeed = legacyColorsFromUserDefaults() ?? TagColorDefaults.seedDefaultColors()
            seed(colorsToSeed)
            try context.save()
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        }

        try saveAndNormalize()
    }

    /// Enforces the app-level rule that tag color names are unique.
    /// In iCloud mode, the newest non-seed record wins so a synced CloudKit record with the same
    /// name replaces a local seeded copy. In local-only mode, the existing library order wins.
    private func reconcileColorNames(in persistedColors: [TagColorDefinition]) throws {
        var didChange = false
        var idRemaps: [UUID: UUID] = [:]
        let grouped = Dictionary(grouping: persistedColors) {
            TagColorLibraryRules.normalizedNameKey($0.name)
        }

        for group in grouped.values {
            guard !group.isEmpty else { continue }

            for color in group where color.isHidden {
                color.isHidden = false
                color.updatedAt = .now
                didChange = true
            }

            guard group.count > 1 else { continue }
            let winner = canonicalColor(from: group)

            for duplicate in group where duplicate !== winner {
                if duplicate.isDefault {
                    winner.setDefault(true)
                }
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
        if let defaultColor = colors.filter(\.isDefault).sorted(by: Self.defaultSort).first {
            return defaultColor
        }

        if duplicateResolutionPolicy == .newestNonDefaultWins {
            let nonDefaultColors = colors.filter { !TagColorDefaults.defaultColorIDs.contains($0.id) }
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

    private func ensureDefaultColorExists() throws {
        let persistedColors = try fetchPersistedColors()
        guard !persistedColors.isEmpty else { return }

        let currentDefaults = persistedColors.filter(\.isDefault)
        let selectedDefault = currentDefaults.sorted(by: Self.defaultSort).first
            ?? persistedColors.first { TagColorLibraryRules.normalizedNameKey($0.name) == TagColorLibraryRules.normalizedNameKey("White") }
            ?? persistedColors[0]

        var didChange = false
        for color in persistedColors {
            let shouldBeDefault = color.id == selectedDefault.id
            if color.isDefault != shouldBeDefault {
                color.setDefault(shouldBeDefault)
                didChange = true
            }
        }

        if didChange {
            try context.save()
        }
    }

    private func applyDefaultColorToMissingTagRecords() throws {
        guard let defaultColorID = try currentDefaultColorID() else { return }
        var didChange = false

        let animals = try context.fetch(FetchDescriptor<Animal>())
        for animal in animals where animal.tagColorID == nil {
            let tagNumber = animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagNumber.isEmpty {
                animal.tagColorID = defaultColorID
                didChange = true
            }
        }

        let tags = try context.fetch(FetchDescriptor<AnimalTag>())
        for tag in tags where tag.colorID == nil {
            if !tag.normalizedNumber.isEmpty {
                tag.colorID = defaultColorID
                didChange = true
            }
        }

        let fieldCheckAnimalChecks = try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>())
        for check in fieldCheckAnimalChecks where check.rosterTagColorID == nil {
            let tagNumber = check.rosterTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagNumber.isEmpty {
                check.rosterTagColorID = defaultColorID
                didChange = true
            }
        }

        if didChange {
            try context.save()
        }
    }

    private func removeRetiredDefaultColors() throws {
        var didChange = false

        for color in try fetchPersistedColors() where TagColorDefaults.retiredDefaultColorIDs.contains(color.id) {
            context.delete(color)
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    private func currentDefaultColorID() throws -> UUID? {
        let persistedColors = try fetchPersistedColors()
        return persistedColors.first(where: { $0.isDefault })?.id
            ?? persistedColors.first { TagColorLibraryRules.normalizedNameKey($0.name) == TagColorLibraryRules.normalizedNameKey("White") }?.id
            ?? persistedColors.first?.id
    }

    private static func defaultSort(_ lhs: TagColorDefinition, _ rhs: TagColorDefinition) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func remapTagColorIDs(_ remaps: [UUID: UUID]) throws {
        guard !remaps.isEmpty else { return }

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
        let key = TagColorLibraryRules.normalizedNameKey(name)
        return try fetchPersistedColors().first { TagColorLibraryRules.normalizedNameKey($0.name) == key }
    }

    private func saveAndNormalize() throws {
        try context.save()
        try removeRetiredDefaultColors()
        try reconcileColorNames(in: fetchPersistedColors())
        try ensureDefaultColorExists()
        try applyDefaultColorToMissingTagRecords()
    }

    private func seed(_ seedColors: [TagColorSnapshot]) {
        var usedNames = Set<String>()

        for color in seedColors {
            let cleanedName = TagColorLibraryRules.normalizedDisplayName(color.name)
            let key = TagColorLibraryRules.normalizedNameKey(cleanedName)
            guard !cleanedName.isEmpty, !usedNames.contains(key) else { continue }

            var snapshot = color
            snapshot.name = cleanedName
            snapshot.prefix = TagColorLibraryRules.normalizedPrefix(color.prefix, fallbackName: cleanedName)
            snapshot.sortOrder = usedNames.count
            context.insert(TagColorDefinition(snapshot: snapshot))
            usedNames.insert(key)
        }
    }

    private func legacyColorsFromUserDefaults() -> [TagColorSnapshot]? {
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey) else {
            return nil
        }

        guard let legacyColors = try? JSONDecoder().decode([LegacyTagColorDefinition].self, from: data) else {
            return nil
        }

        return legacyColors.enumerated().map { index, legacy in
            TagColorSnapshot(
                id: legacy.id,
                name: legacy.name,
                prefix: legacy.prefix,
                rgba: legacy.rgba,
                sortOrder: index,
                isDefault: legacy.isDefault ?? false
            )
        }
    }
}

private struct LegacyTagColorDefinition: Decodable {
    var id: UUID
    var name: String
    var prefix: String
    var rgba: RGBAColor
    var isDefault: Bool?
}
