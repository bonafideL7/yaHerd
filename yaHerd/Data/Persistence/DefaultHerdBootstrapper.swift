//
//  DefaultHerdBootstrapper.swift
//  yaHerd
//

import Foundation
import SwiftData

/// Creates the single local herd scope used by the current app and attaches
/// existing unscoped records to it. This is the first migration step toward
/// sharing a herd as one CloudKit collaboration unit.
enum DefaultHerdBootstrapper {
    static let defaultHerdName = "My Herd"

    static func ensureDefaultHerd(in context: ModelContext) throws {
        let herd = try defaultHerd(in: context)
        var changed = false

        changed = try attachUnscopedRecords(of: Animal.self, in: context, to: herd, keyPath: \Animal.herd) || changed
        changed = try attachUnscopedRecords(of: AnimalTag.self, in: context, to: herd, keyPath: \AnimalTag.herd) || changed
        changed = try attachUnscopedRecords(of: AnimalStatusReference.self, in: context, to: herd, keyPath: \AnimalStatusReference.herd) || changed
        changed = try attachUnscopedRecords(of: StatusRecord.self, in: context, to: herd, keyPath: \StatusRecord.herd) || changed
        changed = try attachUnscopedRecords(of: HealthRecord.self, in: context, to: herd, keyPath: \HealthRecord.herd) || changed
        changed = try attachUnscopedRecords(of: PregnancyCheck.self, in: context, to: herd, keyPath: \PregnancyCheck.herd) || changed
        changed = try attachUnscopedRecords(of: MovementRecord.self, in: context, to: herd, keyPath: \MovementRecord.herd) || changed
        changed = try attachUnscopedRecords(of: Pasture.self, in: context, to: herd, keyPath: \Pasture.herd) || changed
        changed = try attachUnscopedRecords(of: PastureGroup.self, in: context, to: herd, keyPath: \PastureGroup.herd) || changed
        changed = try attachUnscopedRecords(of: TagColorDefinition.self, in: context, to: herd, keyPath: \TagColorDefinition.herd) || changed
        changed = try attachUnscopedRecords(of: WorkingSession.self, in: context, to: herd, keyPath: \WorkingSession.herd) || changed
        changed = try attachUnscopedRecords(of: WorkingQueueItem.self, in: context, to: herd, keyPath: \WorkingQueueItem.herd) || changed
        changed = try attachUnscopedRecords(of: WorkingTreatmentRecord.self, in: context, to: herd, keyPath: \WorkingTreatmentRecord.herd) || changed
        changed = try attachUnscopedRecords(of: WorkingProtocolTemplate.self, in: context, to: herd, keyPath: \WorkingProtocolTemplate.herd) || changed
        changed = try attachUnscopedRecords(of: FieldCheckSession.self, in: context, to: herd, keyPath: \FieldCheckSession.herd) || changed
        changed = try attachUnscopedRecords(of: FieldCheckAnimalCheck.self, in: context, to: herd, keyPath: \FieldCheckAnimalCheck.herd) || changed
        changed = try attachUnscopedRecords(of: FieldCheckFinding.self, in: context, to: herd, keyPath: \FieldCheckFinding.herd) || changed

        if changed {
            herd.updatedAt = .now
        }

        try context.save()
    }

    static func defaultHerd(in context: ModelContext) throws -> Herd {
        var descriptor = FetchDescriptor<Herd>(
            sortBy: [SortDescriptor(\Herd.createdAt)]
        )
        descriptor.fetchLimit = 1

        if let herd = try context.fetch(descriptor).first {
            return herd
        }

        let herd = Herd(name: defaultHerdName)
        context.insert(herd)
        return herd
    }

    private static func attachUnscopedRecords<Model: PersistentModel>(
        of modelType: Model.Type,
        in context: ModelContext,
        to herd: Herd,
        keyPath: WritableKeyPath<Model, Herd?>
    ) throws -> Bool {
        let records = try context.fetch(FetchDescriptor<Model>())
        var changed = false

        for var record in records where record[keyPath: keyPath] == nil {
            record[keyPath: keyPath] = herd
            changed = true
        }

        return changed
    }
}
