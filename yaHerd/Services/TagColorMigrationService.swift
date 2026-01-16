//
//  TagColorMigrationService.swift
//  yaHerd
//

import Foundation
import SwiftData

struct TagColorMigrationService {
    private static let migrationKey = "tagColorMigration.v1.completed"

    static func migrateIfNeeded(context: ModelContext, library: TagColorLibraryStore) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let animals = (try? context.fetch(FetchDescriptor<Animal>())) ?? []
        var changed = false

        for animal in animals where animal.tagColorID == nil {
            if let legacy = animal.tagColor, let def = library.definition(matchingLegacy: legacy) {
                animal.tagColorID = def.id
            } else {
                animal.tagColorID = library.defaultColor.id
            }
            changed = true
        }

        if changed {
            try? context.save()
        }

        defaults.set(true, forKey: migrationKey)
    }
}
